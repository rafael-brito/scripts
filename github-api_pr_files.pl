#! /usr/bin/perl
use strict;
use warnings;
use REST::Client;
use JSON;

# GitHub API endpoint to retrieve pull request files
my $github_url = 'https://api.github.com/repos/:owner/:repo/pulls/:pull_number/files';
my $owner = 'vrsoftbr'; # Replace with the owner of the repository
my $repo = 'VRMaster'; # Replace with the name of the repository
my $pull_number = '4366'; # Replace with the pull request number

# GitHub access token
my $access_token = 'my_github_token'; # Replace with your GitHub access token

# Create REST client
my $client = REST::Client->new();
$client->setHost($github_url);

# Add authorization header
$client->addHeader('Authorization', "token $access_token");

# Substitute owner, repo, and pull request number in the URL
$github_url =~ s/:owner/$owner/g;
$github_url =~ s/:repo/$repo/g;
$github_url =~ s/:pull_number/$pull_number/g;

# Pagination variables
my $page = 1;
my $per_page = 5; # Number of files to fetch per page

# Initialize an array to store all files
my @all_files = ();

# Pagination loop
while (1) {
    # Set pagination parameters
    my $url_with_pagination = $github_url . "?page=$page&per_page=$per_page";
    
    # Pull request files retrieval
    my $response = $client->GET($url_with_pagination);

    # Check if request was successful
    if ($response->responseCode() == 200) {
        my $files_info = decode_json($response->responseContent());
        
        # Check if response is empty, indicating no more data
        last unless @$files_info;

        # Add fetched files to the array
        push @all_files, @$files_info;

        # Increment page number for the next request
        $page++;
    } else {
        print "Failed to retrieve pull request files. Response code: " . $response->responseCode() . "\n";
        last; # Break out of the loop on error
    }
}

# Open a file for writing
open my $fh, '>', 'pr_files.txt' or die "Cannot open file: $!";

# Process all fetched files and write to the file
foreach my $file (@all_files) {
    my $filename = $file->{'filename'};
    my $sha = $file->{'sha'};
    
    # Write file information to the file
    print $fh "Filename: $filename\n";
    print $fh "SHA: $sha\n\n";
}

# Close the file handle
close $fh;

print "Pull request files information has been written to pr_files.txt\n";
