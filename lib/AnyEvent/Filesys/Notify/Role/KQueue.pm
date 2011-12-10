package AnyEvent::Filesys::Notify::Role::KQueue;

use Moose::Role;
use namespace::autoclean;
use AnyEvent;
use Filesys::Notify::KQueue 0.07;
use AnyEvent::Filesys::Notify::Event;
use Carp ();

has _is_dir_flag => ( is => 'rw', isa => 'HashRef[Bool]');

sub _init {
    my $self = shift;

    # Created a new Filisys::Notify::KQueue watcher for dir to watch
    my $kqueue =
        Filesys::Notify::KQueue->new(
            path    => $self->dirs,
            timeout => $self->interval * 1000
        );
    $self->_fs_monitor($kqueue);

    # Create an AnyEvent->io watcher for each watching files
    my %watchers;
    my %is_dir_flag;
    foreach my $file ($kqueue->files) {
        my $fh   = $kqueue->get_fh($file);
        $is_dir_flag{$file} = (-d $file) ? 1 : 0;
        $watchers{$file} = AnyEvent->io(
            fh   => $fh,
            poll => 'r',
            cb   => sub {
                my $events = $kqueue->get_events;
                $self->_process_events(@$events);
                if (
                    grep {
                        $_->{path} eq $file
                        and (
                            $_->{event} eq 'delete'
                            or
                            $_->{event} eq 'rename'
                        )
                    } @$events
                ) {
                    delete $watchers{$file};
                    undef  $watchers{$file};
                }
            }
        );
    }

    $self->_watcher( \%watchers );
    $self->_is_dir_flag( \%is_dir_flag );

    return 1;
}

around '_process_events' => sub {
    my ( $orig, $self, @e ) = @_;

    my @events;
    foreach my $e (@e) {
        my $path = $e->{path};
        my $type =
            ($e->{event} eq 'create') ? 'created':
            ($e->{event} eq 'modify') ? 'modified':
            ($e->{event} eq 'delete') ? 'deleted':
            ($e->{event} eq 'rename') ? 'deleted':
            Carp::croak("Unknown event: $e->{event}");
        push @events,
          AnyEvent::Filesys::Notify::Event->new(
            path   => $path,
            type   => $type,
            is_dir => $self->_is_dir_flag->{$path} ||= ((-d $path) ? 1 : 0),
          );
        delete $self->_is_dir_flag->{$path} if $type eq 'deleted';
    }
    @events = $self->_apply_filter(@events);
    $self->cb->(@events) if @events;

    return \@events;
};

1;
