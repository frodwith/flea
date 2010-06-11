package Flea::Parser::Method;
use base 'Devel::Declare::Parser';
use Devel::Declare::Interface;
Devel::Declare::Interface::register_parser(__PACKAGE__);

sub rewrite {
    my $self  = shift;
    my $parts = $self->parts;
    $self->bail('Not enough arguments') unless @$parts > 1;

    my $re = do {
        my $r = pop @$parts;
        $r = eval { qr{$re->[0]} } or $self->bail('Could not parse route');
        [ $r, undef ]
    };
    push(@$parts, $re);
    $self->new_parts($parts);
}
