# https://rt.perl.org/rt3/Ticket/Display.html?id=117885

# ok    in 5.18.0-threads
# ok    in 5.16.3-threads
# buggy in 5.14.4-threads
# buggy in 5.12.5-threads
# buggy in 5.10.1-threads

use threads;
use POE qw( Pipe::OneWay );

my ($pipe_in, $pipe_out) = POE::Pipe::OneWay->new("pipe");
die "Unable to create pipe"
unless defined $pipe_in and defined $pipe_out;

threads->create(
sub {
my ($pipe_fd) = @_;
IO::Handle->new_from_fd($pipe_fd, "a") or die $!;
},
fileno($pipe_out)
)->join;
