package Koha::Plugin::Com::ByWaterSolutions::RecordsByBiblionumber;

use Modern::Perl;
use base qw(Koha::Plugins::Base);
use HTTP::Tiny;
use JSON;
use Koha::Database;
use C4::Circulation;

our $VERSION = "{VERSION}";
our $MINIMUM_VERSION = "{MINIMUM_VERSION}";

our $metadata = {
    name            => 'Records by Biblionumbers',
    author          => 'Your Name',
    description     => 'Modified plugin to integrate external API for EP numbers and perform checkout operations.',
    date_authored   => '2024-04-30',
    date_updated    => '2024-04-30',
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);
    return $self;
}

sub report {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('output') ) {
        $self->report_step1();
    }
    else {
        $self->report_step2();
    }
}

sub report_step1 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
    my $template = $self->get_template( { file => 'report-step1.tt' } );

    print $cgi->header();
    print $template->output();
}

sub report_step2 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
    my $http = HTTP::Tiny->new();

    # Fetch reader data from external API
    my $response = $http->get('http://192.168.1.29:5000/api/readers');
    my $data = decode_json($response->{content});

    # Extract EP numbers from API response
    my @ep_numbers = map { $_->{ep} } @{ $data->{data} };

    # Initialize Koha schema
    my $schema = Koha::Database->new()->schema();

    # Search for matching EP numbers in Koha
    foreach my $ep_number (@ep_numbers) {
        my $book = $schema->resultset('Biblioitem')->search(
            { ean => $ep_number },
            { join => 'biblio', limit => 1 }
        )->first();

        if ($book) {
            # Perform checkout operation
            my $checkout_success = $self->checkout_book($book);

            if ($checkout_success) {
                $self->display_book_details($book);
            } else {
                warn "Failed to check out book with EP number: $ep_number";
            }
        } else {
            warn "No match found: EP number $ep_number does not match any book in Koha";
        }
    }
}

sub checkout_book {
    my ( $self, $book ) = @_;
    my $item_id = $book->{id};
    my $patron_id = C4::Context->userenv->{number};
    my $branch_code = C4::Context->userenv->{branch};
    my $due_date = '2026-05-30';

    # Perform checkout using Koha's internal circulation function
    my $checkout_success = C4::Circulation::AddIssue(
        { 
            itemnumber => $item_id,
            borrowernumber => $patron_id,
            branch => $branch_code,
            date_due => $due_date,
        }
    );

    return $checkout_success;
}

sub display_book_details {
    my ( $self, $book ) = @_;
    print "Book Title: " . $book->{title} . "\n";
    print "Author: " . $book->{author} . "\n";
    print "EAN Number: " . $book->{ean} . "\n";
}

1;
