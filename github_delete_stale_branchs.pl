#!/usr/bin/env perl

use strict;
use warnings;
use LWP::UserAgent;
use JSON::PP;
use DateTime;
use DateTime::Format::ISO8601;
use Getopt::Long;

# Command line options
my $repo_name = "";
my $owner = "";
my $ghToken = "";
my $months_threshold = 12;
my $dry_run = 1;
my $help = 0;

GetOptions(
    "repo=s"     => \$repo_name,
    "owner=s"    => \$owner,
    "ghToken=s"  => \$ghToken,
    "months=i"   => \$months_threshold,
    "dry-run!"   => \$dry_run,
    "help"       => \$help
) or die "Error in command line arguments\n";

# Display help
if ($help || !$repo_name || !$ghToken) {
    print "Usage: $0 --repo=REPOSITORY [options]\n";
    print "Options:\n";
    print "  --repo=REPOSITORY        Repository name (required)\n";
    print "  --owner=OWNER            Repository owner (default: current user)\n";
    print "  --ghToken=GitHub Token   GitHub user token (required)\n";
    print "  --months=MONTHS          Number of months of inactivity (default: 12)\n";
    print "  --no-dry-run             Actually delete branches (default: dry run only)\n";
    print "  --help                   Display this help message\n";
    exit;
}

# Configuration
$owner ||= "rafael-brito";  # Default to current user if not specified
my @protected_branches = ("main", "stable-4-3", "stable-4-2");

# Headers for GitHub API requests
my $ua = LWP::UserAgent->new;
$ua->default_header('Authorization' => "token $ghToken");
$ua->default_header('Accept' => 'application/vnd.github.v3+json');

# Calculate cutoff date
my $now = DateTime->now;
my $cutoff_date = $now->clone->subtract(months => $months_threshold);
print "Searching for branches not updated in the last $months_threshold months...\n";
print "Cutoff date: " . $cutoff_date->iso8601 . "\n\n";

# Get all branches from the repository
sub get_branches {
    my @branches;
    my $page = 1;
    
    while (1) {
        my $url = "https://api.github.com/repos/$owner/$repo_name/branches?per_page=100&page=$page";
        my $response = $ua->get($url);
        
        if (!$response->is_success) {
            print "Error fetching branches: " . $response->status_line . "\n";
            print "Response: " . $response->content . "\n";
            return ();
        }
        
        my $page_branches = decode_json($response->content);
        last unless @$page_branches;
        
        push @branches, @$page_branches;
        $page++;
    }
    
    return @branches;
}

# Get the last commit date for a branch
sub get_branch_last_commit_date {
    my ($branch) = @_;
    my $sha = $branch->{commit}->{sha};
    my $url = "https://api.github.com/repos/$owner/$repo_name/commits/$sha";
    
    my $response = $ua->get($url);
    if (!$response->is_success) {
        print "Error fetching commit info for " . $branch->{name} . ": " . $response->status_line . "\n";
        return undef;
    }
    
    my $commit_data = decode_json($response->content);
    return $commit_data->{commit}->{committer}->{date};
}

# Main execution
my @branches = get_branches();
print "Found " . scalar(@branches) . " branches in total\n";


# Initialize an array to store all files
# Open a file for writing
open my $fh, '>', "stale-branchs-$repo_name.txt" or die "Cannot open file: $!";

my @stale_branches;
foreach my $branch (@branches) {
    my $branch_name = $branch->{name};
    
    # Skip protected branches
    if (grep { $_ eq $branch_name } @protected_branches) {
        print "Skipping protected branch: $branch_name\n";
        next;
    }
    
    # Get the last commit date
    my $last_commit_date_str = get_branch_last_commit_date($branch);
    next unless $last_commit_date_str;
    
    my $last_commit_date = DateTime::Format::ISO8601->parse_datetime($last_commit_date_str);
    
    # Check if the branch is stale
    if ($last_commit_date < $cutoff_date) {
        my $stale_branch = "Stale branch found: $branch_name\n";
        my $last_updated = "  Last updated: " . $last_commit_date->iso8601 . "\n";

        # Write file information to the file
        print $fh $stale_branch . $last_updated . "\n\n";

        push @stale_branches, $branch_name;
        
        if (!$dry_run) {
            # Delete the branch
            my $delete_url = "https://api.github.com/repos/$owner/$repo_name/git/refs/heads/$branch_name";
            my $delete_response = $ua->delete($delete_url);
            
            if ($delete_response->code == 204) {
                print "  Branch deleted successfully\n";
            } else {
                print "  Error deleting branch: " . $delete_response->content . "\n";
            }
        } else {
            print "  Would delete (dry run)\n";
        }
    }
}

# Close the file handle
close $fh;


print "\nFound " . scalar(@stale_branches) . " stale branches\n";
if ($dry_run) {
    print "This was a dry run. No branches were actually deleted.\n";
    print "Use --no-dry-run to actually delete branches.\n";
}

print "Stale branches information has been written to stale-branchs-$repo_name.txt\n";