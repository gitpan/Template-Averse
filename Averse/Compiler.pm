
use strict;

#----------------------------------
package Template::Averse::Compiler;
#----------------------------------

use Carp;


sub import{}

use vars qw(@return);
sub returning { push @return , @_ };

sub new 
{   my ($class,$comps,$top)=@_;
    my $this = bless {} , $class ;

    if (ref($comps) eq 'ARRAY')
    {   my %hash;
        map { $hash{$_}={name => $_} } @$comps;
        $comps = \%hash;
    }
    elsif (ref($comps) eq 'HASH')
    {   # old Averse
    }
    else
    {   croak "$comps not a component mapping we can handle";
    }

    my $template_name;
    my $template_args;

    if (ref($top) eq '')
    {   $template_name = $top || 'Template';
        my @vars = @{($comps->{$template_name}{vars}||[])};
        $template_args = \@vars;

    }else
    {   $template_name = (keys %$top)[0];
        my @vars = @{($top->{$template_name}{vars}||[])};
        $template_args = \@vars;
    }

    my $block = { name    => $template_name,
                  inst    => '',
                  args    => $template_args,
                  blocks  => [],
                  subs    => [{name=>"$template_name",
                               args=>$template_args,
                               returns=>[]
                              }
                             ],
                  seen    => {},
                };

    $this->{comps}    = $comps;
    $this->{runs}     = [],
    $this->{block}    = $block;
    $this->{current}  = $block;
    $this->{currents} = [];
    $this->{seen}     = {};

    return $this;
}

# document structure
sub BOT
{   my $c=shift; 
    $c->{text}=shift;
}

sub EOT
{   my ($c)=@_;
}

# markers
{ my ($c,$text,$start,$matched,$skipped,$names,$subs,$attrs);
  my %enables;

  sub t { $c=shift; 
          $text=$c->{text}; 
          $subs=$c->{subs}; 
          $names=shift; 
          ($start,$matched,$skipped,$attrs)=@_;
        }

sub Enable 
{   &t; 
shift @$names;
    my $name="@$names";
    $enables{$name} = $matched ;
}

sub Start  
{   &t; 
shift @$names;
    my $name="@$names";

    my @vars = @{($c->{comps}{$name}{vars}||[])};
    
    my $inst = $c->{seen}{$name};
    $c->{seen}{$name}++;
    $inst &&= "::$inst";

    my $sub   = { name=>$name,
                  inst=>$inst,
                  args=>\@vars,
                  returns=>[],
                  marker=>$matched,
                };

    my $block = { name=>$name,
                  inst=>$inst,
                  args=>\@vars,
                  blocks=>[],
                  subs=>[$sub],
                  seen=>{},
                  enable=>$enables{$name},
                  syntax=>['start'],
                  attributes=>$attrs,
                };

    $enables{$name} = ''; # remove enables for next time

    my $lsubs=$#{$c->{current}{subs}};
    push @{$c->{current}{subs}[$lsubs]{returns}} , "callback_$name$inst()";

    push @{$c->{current}{blocks}} , $block;
    push @{$c->{currents}}        , $c->{current};
    $c->{current} = $block;

}

sub Middle
{   &t; 

my $Name = pop @$names;
    my $name="@$names";

    my $b_inst = $c->{current}{inst};

    my $s_inst = $c->{current}{seen}{$name};
    $c->{current}{seen}{$name}++;
    $s_inst &&= "::$s_inst";

    my @vars = @{ ($c->{comps}{$Name}{"${name}_vars"} 
                   || $c->{comps}{$Name}{"vars"} 
                   || []
                  )
                };
    
    my $sub   = { name=>$name,
                  inst=>$s_inst,
                  args=>\@vars,
                  returns=>[],
                  marker=>$matched,
                };
    push @{$c->{current}{subs}} , $sub;
    push @{$c->{current}{syntax}} , $name;


}

sub End    
{   &t;

    if (my $Syntax = $c->{comps}{ $c->{current}{name} }{syntax})
    {   my @found  = ( @{$c->{current}{syntax}}, 'end');
        my $syntax = $Syntax;
        $syntax =~ s/\s*\)/\\s*\)/g; 
        $syntax =~ s/\s+/\\s*\\b/g;

        die  "Syntax error: at offset $start, [$matched]\n",
             "found   : @found\n",
             "expected: $Syntax\n",
             "(tested): $syntax\n"
        unless "@found" =~ m/^$syntax$/;
    }    

    $c->{current} = pop @{$c->{currents}};
}

}#scope

# runs of text
sub aRun
{   my ($c,$offset,$length)=@_;
    my $run = substr(${$c->{text}},$offset,$length);

    foreach my $block (reverse (@{$c->{currents}},$c->{current}))
    {
        next unless my $replace = $c->{comps}{$block->{name}}{replace};
        my @replace = @$replace;
        while ( my($old,$new) = (splice @replace, 0 , 2) )
        {
            $run =~ s/$old/$new/g;
        }
    }


    my $lsubs=$#{$c->{current}{subs}};
    my $returns=$c->{current}{subs}[$lsubs]{returns};

    if ($c->{comps}{$c->{current}{name}}{options}{PerlInterpolate})
    {
        push @{$c->{runs}} , $run;

        # quoting
        my ($l,$r);
        my @unusable = $run =~m/["{}\[\]<>()~!@#%:\/]/g;
        my %unusable;
           @unusable{@unusable}=(1)x@unusable;

        for my $quote (qw( " ~ ! @ % : /),'#')  # qw(#) gives warnings
        {   next if $unusable{$quote};
            $l=$r=$quote;
            last;
        }

        if (!$l)
        {   my %brackets=(qw/ [ ] { } < > [ ]/);
            for my $left (keys %brackets)
            {   my $right = $brackets{$left};
                next if $unusable{$left} or $unusable{$right};
                $l=$left;
                $r=$right;
                last;
            }
        }

        if (!$l)
        {   warn "PerlInterpolate: no good quote for $run";
            $l='{'; $r='}';
        }

        push @{$returns}   , qq{qq${l}$run${r}};

    }

# always use perl inline for now, perhaps should be option, or based on vars
#    elsif($c->{comps}{$c->{current}{name}}{options}{PerlInline})

    else
    {
        my @bits = split /\Q{+\E(.*?)\Q+}\E/s , $run;
        for (my $k = 0; $k < @bits; $k+=2)
        {   if ($bits[$k] ne '')
            {   # literal text -- $bits[$k];
                push @{$c->{runs}} , $bits[$k];
                my $lruns = $#{$c->{runs}};
                push @{$returns} , "$lruns";

            }
            if ($bits[$k+1] ne '')
            {   # macro text   -- $bits[$k+1];
                push @{$c->{runs}} , "{+".$bits[$k+1]."+}";
                push @{$returns}   , $bits[$k+1];
            }
        }    
    }

#    else
#    {
#        push @{$c->{runs}} , $run;
#        my $lruns = $#{$c->{runs}};
#        push @{$returns} , "$lruns";
#    }

}

sub args
{   my $in = shift;
    my @vars = @{$_[0]};
    local $"=",\n$in";
    @vars>0 ? "(@vars) = \@_ if \@_;" : "";
}

sub vars
{   my $in = shift;
    my @vars = @{$_[0]};
    local $"= ",\n$in";
    @vars>0 ? "my (@vars);" : "";
}

sub print_code
{   my $c=shift; 
    local @return;

    returning "{ # template\n";
    returning $c->print_runs();        
    returning "my \$_context={};\n";
    returning $c->print_block(1,$c->{block},[]);
    returning "} # end template\n";
    returning "1;\n";

    @return;
}

sub nice_quote
{   my $quoted = quotemeta($_[0]);
    $quoted =~ s/\\\n/\\n/g;
    $quoted =~ s/\\ / /g;
    return $quoted;
}

sub print_runs
{   my $c=shift; 
    local @return;

    returning "my \@_runs=(\n";
    foreach my $run (@{$c->{runs}})
    {   my $quoted = nice_quote($run);
        $quoted = '"' . $quoted . "\",\n";
        returning $quoted;
    }
    returning ");\n";
    @return;
}

sub attributes
{   my $at=shift;
    return () unless ref($at) eq 'HASH' and keys %$at > 0;

    #"'Attributes'=>{
    my @lines = 
    ((map 
    {"               '$_'=>'".nice_quote($at->{$_})."'" } keys %$at 
     ),
     "              }"
    );
    $lines[0] =~ s/\s*/'Attributes'=>{/;
    @lines;
}

sub visible
{   my $vars=shift;
    return () unless ref($vars) eq 'ARRAY' and @$vars > 0;

    my %seen=();

    #"'Vars'=>{
    my @lines = 
    ((map 
    {"         '$_'=>\\$_" } grep {$seen{$_}++==0} @$vars
     ),
     "        }"
    );
    $lines[0] =~ s/\s*/'Vars'=>{/;
    @lines;
}

sub print_block
{   my ($c,$depth,$block,$visible)=@_;
    local @return;

    my $in = '  ' x $depth ;

    my $Package = $c->{comps}{$block->{name}}{package};
       $Package = $block->{name} if not defined($Package);
       $Package = "${Package}::" unless $Package eq '' or $Package =~ m/::$/;

    returning "\n$in\{ # $block->{name} $block->{inst}\n";
    my $vars = vars("$in      ",$block->{args});
    returning "$in  $vars  # vars \n";

    my @contxt = ();
    foreach my $sub (@{$block->{subs}})
    {   my $sub_name = "${Package}$sub->{name}$block->{inst}$sub->{inst}";
        my $m = nice_quote($sub->{marker});
        push @contxt , "\\&$sub_name=>'$m'";
    }

    my @visible = (@$visible,@{$block->{args}});

    push @contxt , "'-parent'=>\$_context";
    push @contxt , attributes($block->{attributes});
    push @contxt , visible(\@visible);


    my $contxt=
       join("\n$in  , ", @contxt);
    returning "$in  my \$_context = \n";
    returning "$in  { $contxt\n";
    returning "$in  };\n";
    returning "$in  push \@{\$_context->{'-parent'}{'-children'}},\$_context;\n";

    foreach my $subblock (@{$block->{blocks}})
    {   returning $c->print_block($depth+1,$subblock,\@visible);
    }

    my @locals = ();
    my @globs  = ();
    my $end_local = '';
    returning "\n";

    foreach my $sub (@{$block->{subs}})
    {   my $sub_name = "${Package}$sub->{name}$block->{inst}$sub->{inst}";
        push @locals , "local *${Package}$sub->{name}=\\&$sub_name;";
        $end_local   = "local *${Package}end_$block->{name}=\\&$sub_name;";
        push @globs  , "'$sub->{name}'=>\\&$sub_name";

    returning "$in  sub $sub_name\n";
    my $args = args("$in     ",$sub->{args});
    returning "$in  { $args  # args\n";
    returning "$in    return (\n";

        foreach my $return (@{$sub->{returns}})
        {   $return = "\$_runs[$return]" if $return =~ /^\d+$/;
    returning "$in            $return,\n";
        }

    returning "$in           );\n";
    returning "$in  }\n";
    } # end foreach sub

    my $globs=
       join("\n$in              , ", @globs);

    returning "$in  sub callback_$block->{name}$block->{inst}\n";
    returning "$in  {\n";
    returning map 
             {"$in    $_\n"} @locals;
    if (@{$block->{subs}} > 1)
    {
    returning "$in    $end_local\n";
    returning "$in    $end_local #ohwell\n";
    }
    returning "$in    Callback::$block->{name}(\$_context, $globs);\n";
    returning "$in  }\n";

    returning "$in} # end $block->{name}\n";
    @return;
}

1; #EOF

__END__

=head1 SYNOPSIS

 use Template::Averse::Compiler;

 my $compiler = 
    new Template::Averse::Compiler($components,$top_name);

=head1 DESCRIPTION

The compiler generates the code of the compiled template.  A compiler
object is required by a parser.

For complete details, refer to the SEE ALSO section below.

=head1 METHODS

=over 4

=item new components top_name

Create a new compiler object.  

=over 4

=item components 

required - reference to hash or array.

For XML, this parameter can be a reference to an array.  The values
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

Returns a list of strings, which make up the generated code.  

Note: returns a list, not just one string.

=back 4
 
=head1 SEE ALSO

perldoc Template::Averse

perldoc Template::Averse::Parser

perldoc Template::Averse::SAXHandler 

