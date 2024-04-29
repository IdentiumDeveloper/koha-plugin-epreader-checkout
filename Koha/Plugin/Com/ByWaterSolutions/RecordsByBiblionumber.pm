package KohaReaderIntegration::Main;

use Modern::Perl;

use utf8;
use strict;
use warnings;

use C4::Context;
use C4::Items;
use C4::Circulation;
use HTTP::Tiny;
use JSON;
use MIME::Base64;

use C4::Context;
use C4::Auth;
use Koha::Database;
use C4::Checkout;

use base qw(Koha::Plugins::Base);

my $koha_username = 'Dubey_Roh';
my $koha_password = 'Rohit@123';

sub get_auth_header {
    my $credentials = "$koha_username:$koha_password";
    my $encoded_credentials = encode_base64($credentials, '');
    return "Basic $encoded_credentials";
}

our $VERSION = '1.0.0';

sub new {
    my ($class, $args) = @_;
    my $self = $class->SUPER::new({
        metadata => {
              name            => 'Koha Reader Integration',
    	      author          => 'Rohit Dubey',
              description     => 'Plugin to integrate with external API for reader data'
              date_authored   => '2024-04-30',
              date_updated    => "1900-01-01",
              minimum_version => $MINIMUM_VERSION,
              maximum_version => undef,
              version         => $VERSION,
        	},
        args => $args,
    });
    return $self;
}

sub install {
    my ($self, $args) = @_;
    # Perform installation tasks if needed
}

sub uninstall {
    my ($self, $args) = @_;
    # Perform uninstallation tasks if needed
}

sub get_reader_data {
    my $self = shift;

    # Step 1: Fetch reader data from the external API
    my $http = HTTP::Tiny->new();
    my $response = $http->get('http://192.168.1.29:5000/api/readers');

    if ($response->{success}) {
        # Step 2: Parse reader data and extract EP number
        my $data = decode_json($response->{content});
        my $ep_number = $data->{ep};

        # Step 3: Check if the EP number matches biblioitems.ean in Koha
        my $book = $self->find_book_by_ean($ep_number);

        if ($book) {
            # Step 4: Perform checkout if book is found
            my $checkout_success = $self->checkout_book($book);

            if ($checkout_success) {
                # Step 5: Display book details
                $self->display_book_details($book);
            } else {
                warn "Failed to check out the book with EP number: $ep_number";
            }
        } else {
            warn "No match found: EP number $ep_number does not match any book in Koha";
        }
    } else {
        # Handle the error
        warn "Failed to fetch reader data: " . $response->{status};
    }
}

sub find_book_by_ean {
    my ($self, $ep_number) = @_;

    # Use Koha's database schema to search for the book by EP number
    my $schema = Koha::Database->new()->schema();
    my $book;

    # Search for a book where `biblioitems.ean` matches the given EP number
    my $result = $schema->resultset('Biblioitem')
        ->search(
            { ean => $ep_number },
            { join => 'biblio', limit => 1 }
        );

    # Return the first matching book if found
    if (my $biblioitem = $result->first()) {
        $book = {
            id => $biblioitem->biblionumber,
            title => $biblioitem->biblio->title,
            author => $biblioitem->biblio->author,
            ean => $biblioitem->ean,
        };
    }

    return $book;
}


sub checkout_book {
    my ($self, $book) = @_;

    # Use Koha's internal circulation function to perform the checkout
    my $item_id = $book->{id};
    
    # Retrieve the patron ID from the Koha context
    my $patron_id = C4::Context->userenv->{number};
    
    # Retrieve the branch code from the Koha context
    my $branch_code = C4::Context->userenv->{branch};
    
    # Set the due date as needed
    my $due_date = '2026-05-25';
    
    # Variable to capture any error messages
    my $message;
    
    # Perform the checkout using C4::Circulation::AddIssue
    my $checkout_success = C4::Circulation::AddIssue(
        { 
            itemnumber => $item_id,
            borrowernumber => $patron_id,
            branch => $branch_code,
            date_due => $due_date,
            message => \$message,
        }
    );

    # Check if the checkout was successful
    if ($checkout_success) {
        return 1; # Checkout successful
    } else {
        # If checkout failed, log the error message
        warn "Failed to checkout book: $message";
        return 0;
    }
}


sub display_book_details {
    my ($self, $book) = @_;
    
    print "Book Title: " . $book->{title} . "\n";
    print "Author: " . $book->{author} . "\n";
    print "EAN Number: " . $book->{ean} . "\n";
}

1;
