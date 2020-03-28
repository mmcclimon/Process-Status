use strict;
use warnings;
package Process::Status;
# ABSTRACT: a handle on process termination, like $?

use Config ();

=head1 OVERVIEW

When you run a system command with C<system> or C<qx``> or a number of other
mechanisms, the process termination status gets put into C<$?> as an integer.
In C, it's just an integer, and it stores a few pieces of data in different
bits.

Process::Status just provides a few simple methods to make it easier to
inspect.  It exists almost entirely to provide C<as_struct> and C<as_string>,
which provide a simple decomposition of C<$?>.

Methods called on C<Process::Status> without first calling a constructor will
work on an implicitly-constructed object using the current value of C<$?>.  To
get an object for a specific value, you can call C<new> and pass an integer.
You can also call C<new> with no arguments to get an object for the current
value of C<$?>, if you want to keep that ugly variable out of your code.

=method new

  my $ps = Process::Status->new( $status );
  my $ps = Process::Status->new; # acts as if you'd passed $?

=cut

sub _self { ref $_[0] ? $_[0] : $_[0]->new($?); }

sub new {
  my $status = defined $_[1] ? $_[1] : $?;
  return bless \$status, $_[0] if $status >= 0;

  return bless [ $status, "$!", 0+$! ], 'Process::Status::Negative';
}

=method status_code

This returns the value of the integer return value, as you might have found in
C<$?>.

=cut

sub status_code {
  ${ $_[0]->_self }
}

sub pid_t {
  # historical nonsense
  ${ $_[0]->_self }
}

=method is_success

This method returns true if the status code is zero.

=cut

sub is_success  { ${ $_[0]->_self } == 0 }

=method exitstatus

This method returns the exit status encoded in the status.  In other words,
it's the number in the top eight bits.

=cut

sub exitstatus { ${ $_[0]->_self } >> 8   }

=method signal

This returns the signal caught by the process, or zero.

=cut

sub signal     { ${ $_[0]->_self } & 127 }

=method cored

This method returns true if the process dumped core.

=cut

sub cored      { !! (${ $_[0]->_self } & 128) }

=method as_struct

This method returns a hashref describing the status.  Its exact contents may
change over time; it is meant for human, not computer, consumption.

=cut

sub as_struct {
  my $self = $_[0]->_self;

  my $rc = $self->status_code;

  return {
    status_code => $rc,
    ($rc == -1 ? () : (
      exitstatus => $rc >> 8,
      cored      => ($rc & 128) ? 1 : 0,

      (($rc & 127) ? (signal => $rc & 127) : ())
    )),
  };
}

my %SIGNAME;
sub __signal_name {
  my ($signal) = @_;
  unless (%SIGNAME) {
    my @names = split /\x20/, $Config::Config{sig_name};
    $SIGNAME{$_} = "SIG$names[$_]" for (1 .. $#names);
  }

  return($SIGNAME{ $signal } || "signal $signal");
}

=method as_string

This method returns a string describing the status.  Its exact contents may
change over time; it is meant for human, not computer, consumption.

Roughly, you might get things like this:

  exited 0
  exited 92
  exited 2, caught SIGDERP
  exited 2, caught SIGSEGV; dumped core

=cut

sub as_string {
  my $self = $_[0]->_self;
  my $rc   = $$self;
  my $str  = "exited " . ($rc >> 8);
  $str .= ", caught " . __signal_name($rc & 127) if $rc & 127;
  $str .= "; dumped core" if $rc & 128;

  return $str;
}

=method assert_ok

  Process::Status->assert_ok($program_name);

This method does nothing if C<$?> is 0.  Otherwise, it croaks with a message
like:

  your-program-name exited 13, caught SIGNES

If a program name is not provided, "program" is used.

=cut

sub assert_ok {
  my $self = $_[0]->_self;
  return if ref $self eq 'SCALAR' && $$self == 0;
  my $name = @_ > 1 ? $_[1] : "program";

  require Carp;
  Carp::croak("$name " . $self->as_string);
}

{
  package Process::Status::Negative;

  BEGIN { our @ISA = 'Process::Status' }
  sub status_code { $_[0][0] }
  sub pid_t       { $_[0][0] } # historical nonsense
  sub is_success  { return }
  sub exitstatus  { $_[0][0] }
  sub signal      { 0 }
  sub cored       { return }

  sub as_struct {
    return {
      status_code => $_[0][0],
      strerror    => $_[0][1],
      errno       => $_[0][2],
    }
  }

  sub as_string {
    qq{did not run; \$? was $_[0][0], \$! was "$_[0][1]" (errno $_[0][2])}
  }

  sub assert_ok {
    require Carp;
    my $name = @_ > 1 ? $_[1] : "program";
    Carp::croak("$name " . $_[0]->as_string);
  }
}

1;
