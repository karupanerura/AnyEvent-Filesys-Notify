package AnyEvent::Filesys::Notify;

# ABSTRACT: stuff

use Moose;
use AnyEvent;
use File::Find::Rule;
use Cwd qw/abs_path/;
use AnyEvent::Filesys::Notify::Event;
use Carp;
use Try::Tiny;

our $VERSION = '0.02';

has dir         => ( is => 'ro', isa => 'Str',      required => 1 );
# has dirs        => ( is => 'ro', isa => 'ArrayRef', required => 1 );
has cb          => ( is => 'rw', isa => 'CodeRef',  required => 1 );
has interval    => ( is => 'ro', isa => 'Num',      default  => 2 );
has no_external => ( is => 'ro', isa => 'Bool',     default  => 0 );
has _fs_monitor => ( is => 'rw', );
has _old_fs => ( is => 'rw', isa => 'HashRef' );
has _watcher => ( is => 'rw', );

sub BUILD {
    my $self = shift;

    $self->_old_fs( _scan_fs( $self->dir ) );

    if ( $self->no_external ) {
        with 'AnyEvent::Filesys::Notify::Role::Fallback';
    } elsif ( $^O eq 'linux' ) {
        try { with 'AnyEvent::Filesys::Notify::Role::Linux' }
        catch {
            croak
              "Unable to load the Linux plugin. You may want to Linux::INotify2 or specify 'no_external' (but that is very inefficient):\n$_";
        }
    } elsif ( $^O eq 'darwin' ) {
        try { with 'AnyEvent::Filesys::Notify::Role::Mac' }
        catch {
            croak
              "Unable to load the Mac plugin. You may want to install Mac::FSEvents or specify 'no_external' (but that is very inefficient):\n$_";
        }
    } else {
        with 'AnyEvent::Filesys::Notify::Role::Fallback';
    }

    return $self->_init;
}

sub _process_events {
    my ( $self, @raw_events ) = @_;

    # We are just ingoring the raw events for now... Mac::FSEvents
    # doesn't provide much information, so rescan our selves

    my $new_fs = _scan_fs( $self->dir );
    my @events = _diff_fs( $self->_old_fs, $new_fs );

    $self->_old_fs($new_fs);
    $self->cb->(@events) if @events;

    return \@events;
}

# Return a hash ref representing all the files and stats in @path.
sub _scan_fs {
    my (@paths) = @_;

    # Separated into two lines to avoid stat on files multiple times.
    my %files = map { $_ => 1 } File::Find::Rule->in(@paths);
    %files = map { abs_path($_) => _stat($_) } keys %files;

    return \%files;
}

sub _diff_fs {
    my ( $old_fs, $new_fs ) = @_;
    my @events = ();

    for my $path ( keys %$old_fs ) {
        if ( not exists $new_fs->{$path} ) {
            push @events,
              AnyEvent::Filesys::Notify::Event->new(
                path => $path,
                type => 'deleted'
              );
        } elsif ( _is_path_modified( $old_fs->{$path}, $new_fs->{$path} ) ) {
            push @events,
              AnyEvent::Filesys::Notify::Event->new(
                path => $path,
                type => 'modified'
              );
        }
    }

    for my $path ( keys %$new_fs ) {
        if ( not exists $old_fs->{$path} ) {
            push @events,
              AnyEvent::Filesys::Notify::Event->new(
                path => $path,
                type => 'created'
              );
        }
    }

    return @events;
}

sub _is_path_modified {
    my ( $old_path, $new_path ) = @_;

    return   if $new_path->{is_dir};
    return 1 if $new_path->{mtime} != $old_path->{mtime};
    return 1 if $new_path->{size} != $old_path->{size};
    return;
}

# Taken from Filesys::Notify::Simple --Thanks Miyagawa
sub _stat {
    my $path = shift;

    my @stat = stat $path;
    return {
        path   => $path,
        mtime  => $stat[9],
        size   => $stat[7],
        is_dir => -d _,
    };

}

1;

=head1 NAME

AnyEvent::Filesys::Notify - An AnyEvent compatible module to monitor files/directories for changes

=head1 SYNOPSIS

    use AnyEvent::Filesys::Notify;

    my $notifier = AnyEvent::Filesys::Notify->new(
        dir      => [ qw( this_dir that_dir ) ],
        interval => 2.0,    # Optional depending on underlying watcher
        cb       => sub {
            my (@events) = @_;
            # ... process @events ...
        },
    );

    # enter an event loop, see AnyEvent documentation
    Event::loop();

=head1 DESCRIPTION

This module provides a cross platform interface to monitor files and
directories within an L<AnyEvent> event loop. The heavy lifting is done by
L<Linux::INotify2> or L<Mac::FSEvents> on their respective O/S. A fallback
which scans the directories at regular intervals is include for other systems.
See L</IMPLEMENTATIONS> for more on the backends.

Events are passed to the callback (specified as a CodeRef to C<cb> in the
constructor) in the form of L<AnyEvent::Filesys::Notify::Event>s.

=head1 METHODS

=head2 new()

A constructor for a new AnyEvent watcher that will monitor the files in the
given directories and execute a callback when a modification is detected. 
No action is take until a event loop is entered.

Arguments for new are:

=over 4

=item dirs 

An ArrayRef of directories to watch. Required.

=item interval

Specifies the time in fractional seconds between file system checks for
the L<AnyEvent::Filesys::Notify::Role::Fallback> implementation.

Specifies the latency for L<Mac::FSEvents> for the
C<AnyEvent::Filesys::Notify::Role::Mac> implementation.

Ignored for the C<AnyEvent::Filesys::Notify::Role::Linux> implementation.

=item cb

A CodeRef that is called when a modification to the monitored directory(ies) is
detected. The callback is passed a list of
L<AnyEvent::Filesys::Notify::Event>s. Required.

=item no_external

Force the use of the L</Fallback> watcher implementation. This is not
encouraged as the L</Fallback> implement is very inefficient, but it 
does not require either L<Linux::INotify2> nor L<Mac::FSEvents>. Optional.

=back

=head1 WATCHER IMPLEMENTATIONS

=head2 Linux

Uses L<Linux::INotify2> to monitor directories. Sets up an C<AnyEvent-E<gt>io>
watcher to monitor the C<$inotify-E<gt>fileno> filehandle.

=head2 Mac

Uses L<Mac::FSEvents> to monitor directories. Sets up an C<AnyEvent-E<gt>io>
watcher to monitor the C<$fsevent-E<gt>watch> filehandle.

=head2 Fallback

A simple scan of the watched directories at regular intervals. Sets up an
C<AnyEvent-E<gt>timer> watcher which is executed every C<interval> seconds
(or fractions thereof). C<interval> can be specified in the constructor to
L<AnyEvent::Filesys::Notify> and defaults to 2.0 seconds.

This is a very inefficient implementation. Use one of the others if possible.

=head1 Why Another Module For File System Notifications

At the time of writing there were several very nice modules that accomplish
the task of watching files or directories and providing notifications about
changes. Two of which offer a unified interface that work on any system:
L<Filesys::Notify::Simple> and L<File::ChangeNotify>.

L<AnyEvent::Filesys::Notify> exists because I need a way to simply tie the
functionality those modules provide into an event framework. Neither of the
existing modules seem to work with well with an event loop.
L<Filesys::Notify::Simple> does not supply a non-blocking interface and
L<File::ChangeNotify> requires you to poll an method for new events. You could
fork off a process to run L<Filesys::Notify::Simple> and use an event handler
to watch for notices from that child, or setup a timer to check
L<File::ChangeNotify> at regular intervals, but both of those approaches seem
inefficient or overly complex. Particularly, since the underlying watcher
implementations (L<Mac::FSEvents> and L<Linux::INotify2>) provide a filehandle
that you can use and IO event to watch.

This is not slight against the authors of those modules. Both are well 
respected, are certainly finer coders than I am, and built modules which 
are perfect for many situations. If one of their modules will work for you
by all means use it, but if you are already using an event loop, this
module may fit the bill.


=head1 SEE ALSO

Modules used to implement this module L<AnyEvent>, L<Mac::FSEvents>,
L<Linux::INotify2>, L<Moose>.

Alternatives to this module L<Filesys::Notify::Simple>, L<File::ChangeNotify>.

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