package Flea;

use Carp qw(croak);
use Devel::Declare;
use B::Hooks::EndOfScope;
use Scalar::Util qw(blessed);
use Exception::Class ('Flea::Pass' => { alias => 'pass' });
use JSON;

use strict;
use warnings;

our @CARP_NOT = qw(Devel::Declare);

our $_add_handler = sub { croak 'Trying to add handler outside bite' };

for my $keyword (qw(get set put del any)) {
    no strict 'refs';
    *{$keyword} = sub { $_add_handler->(@_) };
};

sub json {
    return [
        200,
        ['Content-Type' => 'application/json; charset=UTF-8'],
        [ JSON::encode_json(shift) ]
    ];
}

sub html {
    return [
        200,
        ['Content-Type' => 'text/html; charset=UTF-8'],
        [ shift ]
    ];
}

sub text {
    return [
        200,
        ['Content-Type' => 'text/plain; charset=UTF-8'],
        [ shift ]
    ];
}

sub method {
    my $methods = shift;
    $_add_handler->(@_) for @$methods;
}

sub http {
    HTTP::Exception->throw(@_);
}

sub handle {
    my ($fh, $type) = @_;
    return [
        200,
        ['Content-Type' => $type || 'text/html; charset=UTF-8'],
        $fh
    ];
}

sub file {
    open my $fh, '<', shift;
    handle($fh, @_);
}

sub _find_and_run {
    my ($handlers, $env) = @_;
    return unless $handlers;
    for my $h (@$handlers) {
        if ($env->{PATH_INFO} =~ $h->{pattern}) {
            my $result = try {
                $h->{handler}->($env);
            }
            catch {
                die $_ unless Flee::Pass->caught($_);
                undef;
            };
            if (try { $result->can('finalize') }) {
                $result = $result->finalize;
            }
            return $result if $result;
        }
    }
    undef;
}

sub bite {
    my %method;
    local $_add_handler = sub {
        my ($m, $r, $c) = @_;
        push(@{$method{$m}}, { pattern => $r, handler => $c });
    };

    return sub {
        my $env    = shift;
        my $result = _find_and_run($method{any}, $env);
        return $result if $result;

        $result    = _find_and_run($method{lc $env->{REQUEST_METHOD}}, $env);
        return $result if $result;
        http 404;
    };
}

sub end_handler {
    on_scope_end {
        my $linestr = Devel::Declare::get_linestr;
        my $offset  = Devel::Declare::get_linestr_offset;
        substr($linestr, $offset, 0, ');');
        Devel::Declare::set_linestr($linestr);
        print STDERR $linestr;
    }
}

sub _install_sub {
    my ($exporter, $from, $importer, $to) = @_;
    no strict 'refs';
    *{"${importer}::$to"} = \&{"${exporter}::$from"};
}

sub _named_method {
    my ($exporter, $from, $importer, $to) = @_;
    Devel::Declare->setup_for(
        $importer,
        {
            $to => {
                const => sub {
                    my ($before, $regex) = Devel::Declare::get_linestr() =~
                        /^(\s*$to\s*)(.*)\s*{\s*$/;
                    croak 'No regex for dispatcher' unless $regex;
                    $regex =~ s/~/\\~/g;
                    Devel::Declare::set_linestr(
                        "$before(qr~$regex~,sub{BEGIN {Flea::end_handler};"
                    );
                    print STDERR Devel::Declare::get_linestr;
                },
            },
        },
    );
    goto &_install_sub;
}

sub _method_keyword {
    my ($exporter, $from, $importer, $to) = @_;
    Devel::Declare->setup_for(
        $importer,
        {
            $to => {
                const => sub {
                    my @matches = Devel::Declare::get_linestr() =~
                        /^(\s*method\s+)
                         ([a-z]+)
                         (?:
                            \s*,\s*
                            ([a-z]+))*
                         \s*(.+)\s*
                         {\s*$/x;
                    my $b = shift(@matches);
                    my $r = pop(@matches);
                    croak 'no regex for dispatcher' unless $r;
                    $r =~ s/~/\\~/g;
                    my $m = '[qw(' . join(' ', @matches) . ')]';
                    Devel::Declare::set_linestr(
                        "$b($m, qr~$r~, sub { BEGIN { Flea::end_handler }"
                    );
                }
            }
        }
    );
    goto &_install_sub;
}

my %export_types;
BEGIN {
    %export_types = (
        (map { $_ => \&_named_method } qw(get post put del any)),
        (map { $_ => \&_install_sub } qw(bite json text html
                                        file handle http pass)),
        method => \&_method_keyword,
    );
}

sub import {
    my ($package, %opts) = @_;
    my $caller = caller;
    my @default = keys %export_types;
    my %exports;
    if (my $only = $opts{only}) {
        croak 'only and except in the same import' if $opts{except};
        @exports{@$only} = @$only;
    }
    else {
        @exports{@default} = @default;
        if(my $except = $opts{except}) {
            delete @exports{@$except};
        }
    }
    if (my $rename = $opts{rename}) {
        for my $key (%$rename) {
            croak "Trying to rename $key, which isn't exported"
                unless $exports{$key};
            $exports{$key} = $rename->{$key};
        }
    }
    for my $key (keys %exports) {
        $export_types{$key}->($package, $key, $caller, $exports{$key});
    }
}

1;

=head1 NAME

Flea - Minimalistic sugar for your Plack

=head1 SYNOPSIS

    # app.psgi, perhaps?
    use Flea;

    my $app = bite {
        get ^/$ {
            file 'index.html';
        }
        get ^/api$ {
            json { foo => 'bar' };
        }
        post ^/resource/(\d+)$ {
            my $request  = request(shift);
            my $id       = shift;
            http 400 unless valid_id($id);
            my $response = response($request)
            $response;
        }
    };

=head1 DESCRIPTION

L<PSGI>/L<Plack> is where it's at. L<Dancer>'s routing syntax is really cool,
but it does a lot of things I don't usually want. What I really want is
Dancer-like sugar as an extremely thin layer over my teeth^H^H^H^H^H PSGI
apps.

=head1 What's with the name?

With all the bad tooth decay jokes, why not call it Gingivitis or something?
That's too much typing.  And it sounds gross.  Also, fleas are small and they
bite you when you're not paying attention.  You have been warned.

=head1 EXPORTS

Flea has a custom exporter to let you do strange things to all of these
keywords, but by default it gives you everything.  See L<EXPORT ARGUMENTS>.

=head2 bite

Takes a block as an argument and returns a PSGI app.  Inside the block is
where you define your route handlers.  If you try defining them outside of a
route block, Flea will bite you.  Note that the routing is done via path_info,
so your app will be 'mountable' via L<Plack::Builder>.

=head2 get, post, put, del, any

C<any> will match any request method, and the others will only match the
corresponding method.  If you need to match some other method or combination
of methods, see L<method>.  Aren't you glad you can rename these?

Next come a regex to match path_info against.  Don't quote it.  God help you
if you quote it.

Last of all comes a block.  This receives the PSGI env as its first argument
and any matches from the regex as extra arguments.  It can return either a raw
PSGI response or something with a finalize() method that returns a PSGI
response (like Plack::Response).

=head2 method

Just like get/post/etc, except you can tack on method names (separated by
commas) to say which methods will match.

    method options ^/regex$ {
    }

    method options, head ^/regex$ {
    }

=head2 json($str)

Returns a full C<200 OK>, C<content-type application/json; charset=UTF-8>
response.  Pass it something that JSON::encode_json can turn into a string.

=head2 text($str)

text/plain; charset=UTF-8.

=head2 html($str)

text/html; charset=UTF-8.  Seeing a pattern?

=head2 file($filename, $mime_type?)

Dump the contents of the file you named.  If you don't give a mime type,
text/html is assumed.

=head2 handle($fh, $mime_type?)

Much like file, except you pass an open filehandle instead of a filename.

=head2 http($code, @args)

Shortcut for HTTP::Exception->throw.  Accepts the same arguments.

=head2 pass

Throws a L<Flea::Pass> exception, which causes Flea to pretend that your
handler didn't match and keep trying other handlers.  By the way, the default
action when no handler is found (or they all passed) is to throw a 404
exception.

=head1 EXPORT ARGUMENTS

The exporter takes keyword arguments (e.g.)

    use Flea (
        only => [qw(bite get post)], 
        rename => { bite => 'something_less_corny' }
    );

=head2 only

Exports only the sugar you ask for.  Pass it an array of names.

=head2 except

Exports everything except what you don't want.  Also takes an array of names.
If you try to mix this with only, Flea will bite you.

=head2 rename

A hashref of names to change.  You might want to do this if one of the
keywords that you want has a name that you don't like.  If you try to rename
something you're not importing, Flea will bite you.

=head1 MATURITY

This module is extremely immature as of this writing.  Not only does the
author have the mind of a child, he has never before tinkered with
Devel::Declare magic and has only consulted its terrible documentation rather
than asking one of the many insane^H^H^H^H^H^Htalented individuals in
#devel-declare.  Therefore, Flea will probably break.  When it does, fork it on
github or send the author a patch or something.  Or go use a real web
framework for grownups, like L<Catalyst>.

=head1 SEE ALSO

L<PSGI>, L<Plack>, L<Dancer>, L<Devel::Declare>
