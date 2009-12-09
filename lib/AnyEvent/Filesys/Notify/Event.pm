package AnyEvent::Filesys::Notify::Event;

use Moose;

has path => ( is => 'ro', isa => 'Str', required => 1 );
has type => ( is => 'ro', isa => 'Str', required => 1 );

sub is_created {
    return shift->type eq 'created';
}
sub is_modified {
    return shift->type eq 'modified';
}
sub is_deleted {
    return shift->type eq 'deleted';
}

1;

=head1 NAME

AnyEvent::Filesys::Notify::Event - Object to report changes in the monitored filesystem

=head1 SYNOPSIS

    use AnyEvent::Filesys::Notify;

    my $notifier = AnyEvent::Filesys::Notify->new(
        dir      => [ qw( this_dir that_dir ) ],
        interval => 2.0,    # Optional depending on underlying watcher
        cb       => sub {
            my (@events) = @_;

            for my $event (@events){
                process_created_file($event->path)  if $event->is_created;
                process_modified_file($event->path) if $event->is_modified;
                process_deleted_file($event->path)  if $event->is_deleted;
            }
        },
    );

=head1 DESCRIPTION

Simple object to encapsulate information about the filesystem modifications.

=head1 METHODS

=head2 path()
    
    my $modified_file = $event->path();

Returns the path to the modified file. 
XXXX: This is the path as given by the user, ie not modified by abs_path

=head2 type()

    my $modificaiton_type $event->type();

Returns the type of change made to the file or directory. Will be one of
C<created>, C<modified>, or C<deleted>.

=head2 is_created()
    
    do_something($event) if $event->is_created;

True if C<$event-E<gt>type eq 'created'>.

=head2 is_modified()

    do_something($event) if $event->is_modified;

True if C<$event-E<gt>type eq 'modified'>.

=head2 is_deleted()

    do_something($event) if $event->is_deleted;

True if C<$event-E<gt>type eq 'deleted'>.

=head1 SEE ALSO

L<AnyEvent::Filesys::Notify::Event>

=head1 BUGS

Please report any bugs or suggestions at L<http://rt.cpan.org/>

=head1 AUTHOR

Mark Grimes, E<lt>mgrimes@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Mark Grimes

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=cut