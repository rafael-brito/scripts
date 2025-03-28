#!/usr/bin/env perl
use strict;
use warnings;
use LWP::UserAgent;
use JSON;
use URI::Escape;
use Time::HiRes qw(sleep);

# Configuration
my $org = ""; # inform the organization name here
my $token = ""; # your github token with repo scope permissions 
my $search_term = "something"; # inform the seach term here
my $output_file = "search_results.txt"; 

my $ua = LWP::UserAgent->new;
$ua->timeout(30);

# Step 1: Get all repositories for the organization
print "Fetching repositories for $org...\n";
my @repos = get_all_repos($org, $token);
print "Found " . scalar(@repos) . " repositories.\n\n";

# Step 2: Search each repository for files containing the search term
my %results = ();
my $repo_count = 0;
my $total_repos = scalar(@repos);

foreach my $repo (@repos) {
    $repo_count++;
    print "[$repo_count/$total_repos] Searching in $repo...\n";
    
    my $files = search_repo_for_term($org, $repo, $search_term, $token);
    if (@$files) {
        $results{$repo} = $files;
        print "  Found " . scalar(@$files) . " files containing '$search_term'\n";
    }
    
    # Respect GitHub's rate limits - add more sophisticated rate limit handling in production
    sleep(45);
}

# Step 3: Generate the report
write_report(\%results, $org, $search_term, $output_file);
print "\nSearch complete! Report generated: $output_file\n";

# Function to get all repositories for an organization
sub get_all_repos {
    my ($org, $token) = @_;
    my @all_repos = ();
    
    my $page = 1;
    my $per_page = 100;
    my $has_more = 1;
    
    while ($has_more) {
        my $req = HTTP::Request->new(
            GET => "https://api.github.com/orgs/$org/repos?page=$page&per_page=$per_page&type=all"
        );
        $req->header('Accept' => 'application/vnd.github.v3+json');
        $req->header('Authorization' => "token $token") if $token;
        
        my $response = $ua->request($req);
        
        if ($response->is_success) {
            my $repos = decode_json($response->content);
            # Extract just the repo names
            push @all_repos, map { $_->{name} } @$repos;
            
            # Check if we've received fewer repositories than requested per page
            $has_more = @$repos == $per_page;
            $page++;
        } else {
            warn "Failed to retrieve repositories (page $page): " . $response->status_line;
            last;
        }
    }
    
    return @all_repos;
}

# Function to search a repository for files containing a term
sub search_repo_for_term {
    my ($org, $repo, $term, $token) = @_;
    my @matching_files = ();
    
    # GitHub's search API
    my $query = uri_escape("$term in:file repo:$org/$repo");
    my $req = HTTP::Request->new(
        GET => "https://api.github.com/search/code?q=$query"
    );
    $req->header('Accept' => 'application/vnd.github.v3+json');
    $req->header('Authorization' => "token $token") if $token;
    
    my $response = $ua->request($req);
    
    if ($response->is_success) {
        my $data = decode_json($response->content);
        foreach my $item (@{$data->{items}}) {
            push @matching_files, {
                path => $item->{path},
                url => $item->{html_url}
            };
        }
    } else {
        if ($response->code == 403) {
            warn "  Rate limit exceeded. Waiting...";
            # Get rate limit reset time and wait
            my $headers = $response->headers;
            my $reset_time = $headers->header('X-RateLimit-Reset');
            if ($reset_time) {
                my $wait_time = $reset_time - time();
                sleep($wait_time > 0 ? $wait_time + 5 : 60);
            } else {
                sleep(60); # Default wait if no header
            }
        } else {
            warn "  Error searching $repo: " . $response->status_line;
        }
    }
    
    return \@matching_files;
}

# Function to write the final report
sub write_report {
    my ($results_ref, $org, $term, $file) = @_;
    my %results = %$results_ref;
    
    open(my $fh, '>', $file) or die "Cannot open output file: $!";
    
    print $fh "SEARCH REPORT: Files containing '$term' across repositories in $org\n";
    print $fh "=" x 70 . "\n";
    print $fh "Generated: " . scalar(localtime()) . "\n\n";
    
    my $total_files = 0;
    my $total_repos_with_matches = 0;
    
    foreach my $repo (sort keys %results) {
        my $files = $results{$repo};
        $total_files += scalar(@$files);
        $total_repos_with_matches++;
        
        print $fh "Repository: $org/$repo\n";
        print $fh "-" x 50 . "\n";
        
        foreach my $file (@$files) {
            print $fh "  - " . $file->{path} . "\n";
            print $fh "    URL: " . $file->{url} . "\n";
        }
        print $fh "\n";
    }
    
    print $fh "=" x 70 . "\n";
    print $fh "SUMMARY:\n";
    print $fh "- Total repositories searched: " . scalar(keys %results) . "\n";
    print $fh "- Repositories with matches: $total_repos_with_matches\n";
    print $fh "- Total files containing '$term': $total_files\n";
    
    close($fh);
}