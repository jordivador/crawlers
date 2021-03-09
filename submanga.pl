use strict;
use warnings;
use feature qw/say/;

use WWW::Mechanize;
use HTML::TreeBuilder 5 -weak;
use Parallel::ForkManager;

my $initialPage           = "https://submanga.io/manga/one-piece-online";    # Add here the page where all manga chapters are shown
my $startingChapterNumber = 0;                                               # Add here the number of chapter to start downloading (they usually start from 0)
my $concurrentDownloads   = 8;                                               # Modify it if required (crappy machine or whatever)

my $mech = WWW::Mechanize->new(autocheck => 0, stack_depth => 0, max_redirects => 0, timeout => 10);
$mech->agent_alias('Windows Mozilla');

my $response = $mech->get($initialPage);

if (!$response->is_success) {
	die "Not able to access to $initialPage";
}

my $tree                = HTML::TreeBuilder->new_from_content($response->decoded_content);
my $listOfChaptersTable = $tree->look_down(_tag => 'div', class => qr/capitulos-list/);
my @linkToChapters      = $listOfChaptersTable->look_down(_tag => 'a');

say "Total chapters to download " . scalar(@linkToChapters);

__downloadAllChapters($mech, reverse @linkToChapters);

sub __downloadAllChapters {
	my ($mech, @linkToChapters) = @_;

	my $pm = Parallel::ForkManager->new($concurrentDownloads);

	foreach my $chapter (@linkToChapters) {
		my ($chapterNumber) = $chapter->attr('href') =~ /\/(\d+)$/;
		next if $chapterNumber < $startingChapterNumber;
		$pm->start and next;
		my $chapterName = $chapter->as_text();
		my $chapterLink = $chapter->attr('href');

		my $dir = "/tmp/$chapterName";
		`mkdir '$dir'`;

		my $endPoint;
		my $linkToPage;
		my $page = 0;
		do {
			$page++;
			$linkToPage = "$chapterLink/$page";
			say "$page => Downloading $linkToPage...";
			my $response = $mech->get($linkToPage);
			if (!$response->is_success) {
				die "Stopping... Failed to download $linkToPage...";
			}

			my $pageContent = HTML::TreeBuilder->new_from_content($response->decoded_content);
			$endPoint = $pageContent->look_down(_tag => 'div', class => 'terminado');

			if (!$endPoint) {
				my $image     = $pageContent->look_down(_tag => 'img', class => qr/scan-page/);
				my $fileName  = $image->attr('alt');
				my $imageLink = $image->attr('src');
				say "Downloading to $dir/$fileName.jpg";

				my $r = $mech->get($imageLink);
				open my $fh, '>:raw', "$dir/$fileName.jpg";
				print $fh $r->decoded_content;
				close $fh;
			}
		} while (!$endPoint);

		say "Total $page pages downloaded on $chapterLink";
		$pm->finish(0);
	}
	$pm->wait_all_children;
}
