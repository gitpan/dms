=head1 NAME

Document::Manager

=head1 SYNOPSIS

my $repository = new Document::Manager;

my $doc_id = $repository->add($filename);

my $filename = $repository->checkout($dir, $doc_id);

=head1 DESCRIPTION

This module provides a simple interface for managing a collection of
revision-controlled documents.  

=head1 FUNCTIONS

=cut

package Document::Manager;

use strict;

use vars qw($VERSION %FIELDS);
our $VERSION = '0.02';

use fields qw(
              _repository_path
              _repository_permissions
              _next_id
              _error_msg
              );


=head2 new($confighash)

Establishes the repository interface object.  You must pass it the
location of the repository, and optionally can indicate what permissions
to use (0600 is the default).

If the repository already exists, indicate where Document::Manager
should start its numbering (e.g., you may want to store this info
in a config file or something between invokations...)

=cut

sub new {
    my ($this, %args) = @_;
    my $class = ref($this) || $this;
    my $self = bless [\%FIELDS], $class;

    while (my ($field, $value) = each %args) {
	$self->{"|$field"} = $value
	    if (exists $FIELDS{"_$field"});
    }

    # Specify defaults
    $self->{_repository_dir} ||= '/var/dms';
    $self->{_repository_permissions} ||= 0600;
    $self->{_next_id} || 1;
    return $self;
}

sub _set_error {
    my $self = shift;
    $self->{_error_msg} = shift;
}

=head2 get_error()

Retrieves the most recent error message

=cut

sub get_error {
    my $self = shift;
    return $self->{_error_msg};
}

=head2 repository_path($doc_id, $rev_number)

Returns a path to the location of the document within the repository
repository. 

=cut

sub repository_path {
    my $self = shift;
    my $doc_id = shift || return undef;
    my $rev_number = shift;
    $self->_set_error('');

    my $repo = $self->{_repository_path};

    # Verify the repository exists
    if (! $repo || ! -d $repo) {
	$self->_set_error("Document repository '$repo' does not exist");
	return undef;
    } 


    # Millions subdir
    if ($doc_id > 999999) {
        $repo = catdir($repo,
		       sprintf("M%03d", int($doc_id/1000000)));
    }

    # Thousands subdir
    if ($doc_id > 999) {
        $repo = catdir($repo,
		       sprintf("k%03d", int($doc_id/1000)%1000));
    }

    # Ones subdir
    $repo = catdir($repo,
		   sprintf("%03d", $doc_id % 1000));

    # Get the current revision number by looking for highest numbered
    # file or directory
    if (! $rev_number) {
	if (! opendir(DIR, $repo)) {
	    $self->_set_error("Could not open directory '$repo' ".
			      "to find the max revision number: $!");
	    return undef;
	}
	my @files = sort { $a <=> $b } grep { /^\d+$/ } readdir(DIR);
	$rev_number = shift @files;
	closedir(DIR);
    }

    $repo = catdir($repo,
		   sprintf("%03d", $rev_number));

    return $repo;
}


=head2 add()

Adds a new document to the repository.  Establishes a new document
ID and returns it.

If you wish to simply register the document ID without actually
uploading a file, send a zero-byte temp file.

Specify a $revision if you want the document to start at a revision
number other than 0.

Returns undef on failure.  You can retrieve the error message by
calling get_error().

=cut

sub add {
    my $self = shift;
    my $filename = shift;
    my $revision = shift || 0;
    $self->_set_error('');

    if (! $filename || ! -e $filename) {
	$self->_set_error("Invalid filename specified to add()");
	return undef;
    }

    my $doc_id = $self->{_next_id};

    my $repo = $self->repository_path($doc_id, $revision);

    eval { mkpath([$repo], 0, $self->{_repository_permissions}) };
    if ($@) {
	$self->_set_error("Error adding '$filename' to repository:  $@");
	return undef;
    }

    # Install the file into the repository
    if (! copy($filename, catfile($repo, $filename)) ) {
	$self->_set_error("Error copying '$filename' to repository: $!");
	return undef;
    }

    $self->{_next_id}++;
    return $doc_id;
}

=head2 checkout()

Checks out a copy of the document specified by $doc_id, placing
a copy into the directory specified by $dir.  By default it will
return the most recent revision, but a specific revision can be
retrieved by specifying $revision.

Returns the filename copied into $dir on success.  If there is an error,
it returns undef.  The error message can be retrieved via get_error().

=cut

sub checkout {
    my $self = shift;
    my $dir = shift;
    my $doc_id = shift;
    my $revision = shift;
    $self->_set_error('');

    if (! $doc_id || $doc_id != /^\d+/) {
	$self->_set_error("Invalid doc_id specified to checkout()");
	return undef;
    }

    if (! $dir || ! -d $dir) {
	$self->_set_error("Invalid dir specified to checkout()");
	return undef;
    }

    my $repo = $self->repository_path($doc_id, $revision);

    if (! opendir(DIR, $repo)) {
	$self->_set_error("Could not open '$repo' to checkout file: $!");
	return undef;
    }
    my @files = sort grep {-f && !/^\./ } readdir DIR;
    closedir(DIR);
    my $filename = shift @files;

    if (! copy(catfile($repo, $filename), $dir)) {
	$self->_set_error("Error copying '$filename' to destination '$dir': $!");
	return undef;
    }

    return $filename;
}


1;
