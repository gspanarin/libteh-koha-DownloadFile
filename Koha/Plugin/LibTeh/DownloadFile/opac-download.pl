#!/usr/bin/perl

use Modern::Perl;
use FindBin qw($Bin);

# $Bin = .../plugins/Koha/Plugin/LibTeh/DownloadFile
# Add the instance plugin root (.../plugins) to @INC.
use lib "$Bin/../../../..";

use CGI;
use Koha::Plugin::LibTeh::DownloadFile;

my $cgi = CGI->new;

my $plugin = Koha::Plugin::LibTeh::DownloadFile->new({
    cgi => $cgi,
});

if ( !$plugin ) {
    print $cgi->header(
        -status  => '503 Service Unavailable',
        -type    => 'text/plain',
        -charset => 'UTF-8',
    );
    print "Koha plugins are not enabled.\n";
    exit 0;
}

$plugin->download();
exit 0;
