
use strict;
#----------------------------------
package Template::Averse::CallbackStubs;
#----------------------------------
use vars qw(@ISA);
use Template::Averse::Compiler;
use base qw( Template::Averse::Compiler );

sub import{}

*vars=\&Template::Averse::Compiler::vars;
sub args
{   my $in = shift;
    my @vars = @{$_[0]};
    local $"=",\n$in";
    @vars>0 ? "@vars" : "";
}

use vars qw(@return);
sub returning { push @return , @_ };

sub print_code
{   my $c=shift; 
    local @return;

    returning q{
use vars qw(@return);
sub returning { push @return , @_ };
sub Callback::AUTOLOAD {warn "AUTOLOAD of @_"; return()}
};

    returning $c->print_block(1,$c->{block});
    @return;
}

sub print_block
{   my ($c,$depth,$block)=@_;
    local @return;

    my $Package = $c->{comps}{$block->{name}}{package};
       $Package = $block->{name} if not defined($Package);
       $Package = "${Package}::" unless $Package eq '' or $Package =~ m/::$/;

    if ($depth > 1)
    {

        my $vars = vars('        ',$block->{args});

        returning "
sub Callback::$block->{name}
{
    my (\$context,\%funcs) = \@_;
    $vars
    local \@return;
";
    
        foreach my $sub (@{$block->{subs}})
        {   
            my $sub_name = "${Package}$sub->{name}$block->{inst}$sub->{inst}";
            my $in = '               ' . (' 'x length($sub_name));
            my $args = args($in,$sub->{args});
            returning "
    returning $sub_name\($args);";
        }

        returning "

    \@return;
}
";  
    } # end if depth

    foreach my $subblock (@{$block->{blocks}})
    {   returning $c->print_block($depth+1,$subblock);
    }
    @return;
} # end print_block

1;


__END__

=head1 SYNOPSIS

 use Template::Averse::CallbackStubs;

 my $compiler = 
    new Template::Averse::CallbackStubs($components,$top_name);

=head1 DESCRIPTION

This compiler generates a set of stubs for the callback subs that are
required by a template.  The generated code may be convenient when
developing the callback code.

This is used by the two provided template compilers, averse-tcc and
averse-tcxml.

I do not imagine a regular script would use this compiler object.

=head1 METHODS

=over 4

=item new components top_name

Create a new compiler object.  

=over 4

=item components

required - reference to hash or array.

For XML only, this parameter can be a reference to an array.  The values
should be the local names of the tags to recognize.  In this case the tags
to be recognized cannot be associated with a namespace in the xml.

Otherwise this parameter is a reference to a hash, as documented
elsewhere.

=item top_name 

optional - a string

The name of the component that is the entire template.

The default value is `Template::Template'.

=back 4

=item print_code

Return a list of strings that are code of the callback stubs.

=back 4
 
=head1 SEE ALSO

examine the included compilers for more details.
