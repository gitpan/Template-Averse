use strict;

#-------------------------------
package Template::Averse::Parser;
#-------------------------------

sub import{}

sub gen_re 
{   my ($names , $marker ) = @_ ;
    $names = join ',' , map { '"'.quotemeta($_).'"' } @$names ;
    qq{(?:$marker(?{\@names=($names)}))} ;
}

sub gen_what
{   my ($names , $what) = @_;
    my $re;
    my $name = $names->[0];

    if (!ref($what))
    {   $re = gen_re( $names , $what  );
    }

    elsif ( ref($what) eq 'HASH')
    {   my (@a,$subname);
        while ( my($subname,$marker) = each %{$what})
        {   $names->[0] = $subname;
            push @a , gen_re( $names , $marker );
        }
        $re = join '|' , @a;
    }

    elsif (ref($what ) eq 'ARRAY')
    {   my @whats = @$what;
        my @a;
        while ( my($subname,$marker) = (splice @whats , 0 , 2) )
        {   $names->[0] = $subname;
            push @a , gen_re( $names , $marker );
        }
        $re = join '|' , @a;
    }

    else
    {   die "@$names, $what: not string, array or hash";
    } 

    return $re;
}


sub gen_one_rule_tables
{   my ($name,$rule)=@_;
    use vars qw(%rule);
    local *rule=$rule;
    my %res;
    my @names = ('',$name);

    foreach my $which (qw(enable start middle end))
    {   $names[0] = $which;
        if ( $rule{$which} )
        {   ( $res{$which} ) = gen_what(\@names,$rule{$which});
        }
    }
    $res{continue} = join '|' , grep {$_} ($res{middle},$res{end});
    return (\%res);
}

sub compile_component_definitions
{   my ($comps)=@_;

    foreach my $name (keys %$comps)
    {   $comps->{$name}{res} = gen_one_rule_tables($name,$comps->{$name});
    }
}

sub build_re
{   use vars qw(%comps %state @stack);
    local (*comps,*state,*stack)=@_;

    my $re  = join '|' , 
              grep { $_ }
              ( $stack[$#stack]{re}
              , map { ($comps{$_}{enable} && !$state{$_}{enabled}) ?
                      $comps{$_}{res}{enable} : $comps{$_}{res}{start}
                    } 
                keys %comps 
              );

    use re 'eval';
    return qr/$re/;
}

sub new
{   my ($class,$comps,$compiler)=@_;
    my %parse;
    compile_component_definitions($comps);
    $parse{comps}=$comps;
    $parse{state}={};
    $parse{stack}=[undef];
    $parse{compiler}=$compiler;

    return bless \%parse , $class ;
}

sub parse
{   my ($p,$text)=@_;

    my ($comps,$state,$stack,$compiler) = @$p{qw(comps state stack compiler)};

    # 0 is the offset into string

    $compiler->BOT(\$text);

    my $i;
    my $start;
    my $end;
    my $skipping;
    my $matched;
    my $at=0;

    use vars qw( @names );

    my $re = build_re($comps, $state, $stack);

    while ( $text =~ m/$re/g )
    {
        $i++;
        $start = $-[0]; # number, offset into string of start of match
        $end   = $+[0]; # number, offset into string of end of match (1 past)
        $skipping = $+; # a string, extracted by the last matching "()"
        $matched  = $&; # a string, the string that matched

        $compiler->aRun($at,$start+length($skipping)-$at);
        $at = $start+length($matched);

        if ($names[0] eq 'enable')
        {
            $compiler->Enable([@names],$start,$matched,$skipping);

            $state->{$names[1]}{enabled}=1;
            $re = build_re($comps, $state, $stack);
        }

        elsif ($names[0] eq 'start')
        {

            $compiler->Start([@names],$start,$matched,$skipping);

            if ( $comps->{$names[1]}{end} )
            {   push @$stack , { re=>$comps->{$names[1]}{res}{continue} ,
                                 name=>$names[1] ,
                               } ;
            }
            else
            {   $compiler->End([@names],$start,$matched,$matched);
            }

            $state->{$names[1]}{enabled}=0;
            $re = build_re($comps, $state, $stack);
        }

        elsif ($names[0] eq 'end')
        {   
            $compiler->End([@names],$start,$matched,$skipping);        

            pop @$stack ;
            $re = build_re($comps, $state, $stack);
        }

        else # must be a middle
        {   
            $compiler->Middle([@names],$start,$matched,$skipping);
        }

    }

    $compiler->aRun($at,length($text)-$at);
    $compiler->EOT();

}

1;


__END__

=head1 SYNOPSIS

 use Template::Averse::Parser;
 use Template::Averse::Compiler;

 my $components = { read perldoc Template::Averse for the 
                    correct hash syntax.  Look for MARKERS.
                  };

 my $compiler = new Template::Averse::Compiler($components,'top_name');

 my $parser   = new Template::Averse::Parser($components,$compiler);

 my $lines = do {local $/=undef; <TEMPLATE>};

 $parser->parse($_);

 my @code = $compiler->print_code();

 -- OR --

 while (<TEMPLATE>) # read some unit of data
 {
    $parser->parse($_);
 }

=head1 DESCRIPTION

The parser uses the component definitions and a compiler to find the
components in the template, and feed them to the compiler.

A template can be fed to the parser in chunks, but each marker must be
completely contained within a single chunk.  If a marker does not span
line breaks then lines can be parsed one at a time.  Otherwise some larger
chunk must be used such that each marker can be guaranteed to be contained
within a single chunk.  (A componenet can span over chunks, it's just each
marker that must be within  single chunk.)


=head1 METHODS

=over 4

=item new components compiler

Create a new parser object.  

=over 4

=item components 

required - reference to hash.

Note: the parser does not accept a reference to an array.

This parameter is a reference to a hash, as documented
elsewhere.

=item compiler

An Averse compiler object.

=back 4

=item parse chunk

chunk is a string which is the next length of text to be parsed.  The
description has some notes about the chunks of data, so please read it.

=back 4
 
=head1 SEE ALSO

perldoc Template::Averse

perldoc Template::Averse::SAXHandler 

