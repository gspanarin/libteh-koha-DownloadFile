package Koha::Plugin::LibTeh::DownloadFile;

use Modern::Perl;

use base qw(Koha::Plugins::Base);
use utf8;

use CGI;
use C4::Auth qw(get_template_and_user);
use C4::Context;
use C4::Output qw(output_html_with_http_headers);
use Koha::Biblios;
use Koha::Patrons;
use Koha::UploadedFiles;
use Koha::AuthorisedValues;
use Koha::Exception;
use Socket qw(inet_pton AF_INET AF_INET6);
use Encode qw(encode_utf8);
use Dumper;

our $VERSION = '0.2.0';

sub new {
    my ( $class, $args ) = @_;
    $args ||= {};
    my $self = $class->SUPER::new($args);

    $self->{metadata} = {
        name            => 'DownloadFile',
        author          => 'Hennadii Panarin',
        date_authored  => '2026-10-05',
        date_updated   => '2026-10-05',
        minimum_version => '23.11',
        maximum_version => undef,
        version         => $VERSION,
        description     => 'Плагін надає можливості завантаження файлів у сховище ILS Koha та керування правами читацького доступу для їх перегляду',
        type            => 'opac',
    };

    return $self;
}

sub configure {
    my ( $self, $args ) = @_;

    $self->_ensure_authorised_values;

    my $input = CGI->new;
    my $template = $self->get_template({ file => 'templates/configure.tt' });

    if ( ( $input->param('op') // '' ) eq 'cud-save' ) {
        my @rights = qw(admin authorized_user local open_acces staff);

        for my $right (@rights) {
            my $message = $input->param("denial_$right") // '';
            $self->store_data({
                "denial_$right" => $message
            });
        }


        

        $self->store_data({
            key   => 'local_networks',
            value => $input->param('local_networks') // '',
        });

        $template->param(saved => 1);
    }

    my %denial_messages;
    for my $right (qw(admin authorized_user local open_acces staff)) {
        $denial_messages{$right} = $self->retrieve_data("denial_$right") // '';
    }

    $template->param(
        PLUGIN_CLASS => $self->{class},
        denial_messages => \%denial_messages,
        local_networks  => $self->retrieve_data('local_networks') // '',
    );

    return $self->output_html(
        $template->output
    );
}

#sub tool {
#    my ( $self, $args ) = @_;
#    $self->configure($args);
#}


sub install {
    my ( $self ) = @_;
    $self->_ensure_authorised_values;
    return 1;
}

sub uninstall {
    my ( $self ) = @_;
    # Do not remove authorised values on uninstall: they may be used elsewhere.
    return 1;
}

sub _ensure_authorised_values {
    my ( $self ) = @_;

    my $dbh = C4::Context->dbh;

    my $category = 'file_access_rights';

    my $exists = $dbh->selectrow_array(
        q{
            SELECT 1
            FROM authorised_value_categories
            WHERE category_name = ?
        },
        undef,
        $category
    );

    return 1 if $exists;

    $dbh->do(
        q{
            INSERT INTO authorised_value_categories (category_name, is_system)
            VALUES (?, 0)
        },
        undef,
        $category
    );

    my @values = (
        [ 'admin',           'Адміністратор системи' ],
        [ 'authorized_user', 'Зареєстрований читач' ],
        [ 'local',           'Локальний доступ у мережі бібліотеки' ],
        [ 'open_acces',      'Відкритий доступ' ],
        [ 'staff',           'Співробітник бібліотеки' ],
    );

    for my $item (@values) {
        my ( $code, $description ) = @$item;

        $dbh->do(
            q{
                INSERT INTO authorised_values
                    (category, authorised_value, lib)
                VALUES (?, ?, ?)
            },
            undef,
            $category,
            $code,
            $description
        );
    }

    return 1;
}

sub download {
    my ( $self ) = @_;

    my $input = CGI->new;

    my $biblionumber = $input->param('biblionumber');
    my $hashvalue    = $input->param('id');

    if ( !defined($biblionumber) || $biblionumber !~ /^\d+$/ || !defined($hashvalue) || $hashvalue !~ /^[0-9a-fA-F]{40}$/ ) {
        return $self->_access_denied(
            undef,
            'Некоректні параметри запиту.'
        );
    }

    my $biblio = Koha::Biblios->find($biblionumber);

    if ( !$biblio ) {
        return $self->_access_denied(
            undef,
            'Бібліографічний запис не знайдено.'
        );
    }

    my $file = Koha::UploadedFiles->search({
        hashvalue => lc $hashvalue,
    })->next;

    if ( !$file ) {
        return $self->_access_denied(
            undef,
            'Файл не знайдено.'
        );
    }

    my $record = eval { $biblio->metadata->record };

    if ( !$record ) {
        return $self->_access_denied(
            undef,
            'Не вдалося прочитати бібліографічний запис.'
        );
    }

    my @rights = $self->_rights_for_file( $record, $hashvalue );

    if ( !@rights ) {
        return $self->_access_denied(
            undef,
            'Файл не прив’язаний до цього бібліографічного запису.'
        );
    }

    my ( $allowed, $denied_right ) = $self->_check_access( \@rights );

    if ( !$allowed ) {
        return $self->_access_denied(
            $denied_right,
            undef
        );
    }

    my $fh = $file->file_handle;

    if ( !$fh ) {
        return $self->_access_denied(
            undef,
            'Не вдалося відкрити файл.'
        );
    }

    my $cgi = $input;
    print encode_utf8( $cgi->header( $file->httpheaders ) );

    while ( my $line = <$fh> ) {
        print $line;
    }

    close $fh;

    return;
}

sub _rights_for_file {
    my ( $self, $record, $hashvalue ) = @_;

    my @rights;

    for my $field ( $record->fields('856') ) {
        my @urls = map { $_ // '' } $field->subfields('u');

        my $matches = 0;

        for my $url (@urls) {
            if ( index( lc($url), lc($hashvalue) ) >= 0 ) {
                $matches = 1;
                last;
            }
        }

        next unless $matches;

        my @l_values = map { $_ // '' } $field->subfields('l');

        # Empty or missing $l means unrestricted/open access.
        if ( !@l_values || !grep { defined($_) && length($_) } @l_values ) {
            return ('open_acces');
        }

        push @rights, grep { defined($_) && length($_) } @l_values;
    }

    my %seen;
    return grep { !$seen{$_}++ } @rights;
}

sub _check_access {
    my ( $self, $rights ) = @_;

    my $user = $self->_current_user;

    for my $right (@$rights) {
        my $normalized = lc $right;
        $normalized =~ s/^\s+|\s+$//g;

        if ( $normalized eq 'open_acces' ) {
            return (1, undef);
        }

        if ( $normalized eq 'authorized_user' ) {
            return (1, undef) if $user;
            next;
        }

        if ( $normalized eq 'staff' ) {
            return (1, undef)
                if $user && ($user->{categorycode} // '') eq 'STAFF';
            next;
        }

        if ( $normalized eq 'admin' ) {
            return (1, undef)
                if $user && ($user->{categorycode} // '') eq 'admin';
            next;
        }

        if ( $normalized eq 'local' ) {
            return (1, undef) if $self->_is_local_ip;
            next;
        }
    }

    # Return the first configured right as the reason to display.
    return (0, $rights->[0]);
}

sub _current_user {
    my ( $self ) = @_;

    my $session = C4::Auth::get_session( CGI->new );
    return unless $session;

    my $borrowernumber = $session->param('borrowernumber');
    return unless $borrowernumber;

    my $patron = Koha::Patrons->find($borrowernumber);
    return unless $patron;

    return {
        borrowernumber => $patron->borrowernumber,
        categorycode   => $patron->categorycode,
    };
}

sub _is_local_ip {
    my ( $self ) = @_;

    my $input = CGI->new;
    my $ip = $input->remote_addr // '';

    my $config = $self->retrieve_data('local_networks') // '';
    my @networks = grep { /\S/ } split /\r?\n/, $config;

    return 0 unless @networks;

    for my $network (@networks) {
        $network =~ s/^\s+|\s+$//g;
        next unless length $network;

        return 1 if _ip_matches_network( $ip, $network );
    }

    return 0;
}

sub _ip_matches_network {
    my ( $ip, $network ) = @_;

    # Exact IP.
    return 1 if $ip eq $network;

    my $addr_family = index($ip, ':') >= 0 ? AF_INET6 : AF_INET;

    # CIDR.
    if ( $network =~ m{^([^/]+)/(\d+)$} ) {
        my ( $base, $prefix ) = ($1, $2);

        my $ip_bin   = inet_pton($addr_family, $ip);
        my $base_bin = inet_pton($addr_family, $base);

        return 0 unless defined($ip_bin) && defined($base_bin);

        my $bits = $addr_family == AF_INET ? 32 : 128;
        return 0 if $prefix > $bits;

        my $bytes = int($prefix / 8);
        my $remaining = $prefix % 8;

        return 0 if substr($ip_bin, 0, $bytes) ne substr($base_bin, 0, $bytes);

        if ($remaining) {
            my $mask = (0xFF << (8 - $remaining)) & 0xFF;
            return 0
                if ( (ord(substr($ip_bin, $bytes, 1)) & $mask)
                    != (ord(substr($base_bin, $bytes, 1)) & $mask) );
        }

        return 1;
    }

    # Explicit range: start-end.
    if ( $network =~ m{^(.+?)\s*-\s*(.+)$} ) {
        my ($start, $end) = ($1, $2);

        my $ip_bin    = inet_pton($addr_family, $ip);
        my $start_bin = inet_pton($addr_family, $start);
        my $end_bin   = inet_pton($addr_family, $end);

        return 0 unless defined($ip_bin) && defined($start_bin) && defined($end_bin);

        return $ip_bin ge $start_bin && $ip_bin le $end_bin;
    }

    return 0;
}

sub _access_denied {
    my ( $self, $right, $explicit_message ) = @_;

    my $input = $self->{'cgi'} || CGI->new;
    my $template = $self->get_template({
        file => 'templates/denied.tt',
    });

    my $message = $explicit_message;

    if ( !$message && $right ) {
        $message = $self->retrieve_data("denial_$right") // '';
        $message ||= 'Доступ до цього файлу заборонено.';
    }

    $template->param(
        denied_right   => $right,
        denial_message => $message,
    );

    return $self->output_html(
        $template->output
    );
}

1;
