
use strict;

#----------------------------------
package Template::Averse::SAXHandler;
#----------------------------------
use Data::Dumper;
use Carp;

use base qw(XML::SAX::Base);

sub new 
{   my ($class,$cc,$trans)=@_;
    my $comps = $cc->{comps};
    my $this  = bless {} , $class ;
    

    if (ref($trans) eq 'HASH')
    {   ;
    }
    elsif ($trans ne '')
    {   croak "$trans not an xmlns translation we can handle";
    }
    else
    {   my %hash;
        foreach my $name (keys %$comps)
        {   my $xmlns = $comps->{$name}{NamespaceURI};
            if (my $parent = $comps->{$name}{parent} and !$xmlns)
            {   $xmlns = $comps->{$parent}{NamespaceURI};
            }
            my $tag = $comps->{$name}{LocalName} || $name;
            $xmlns = "{$xmlns}$tag";
            $hash{$xmlns} = $name;
        }
        $trans = \%hash;        
    }

    $this->{xmlns}  = $trans;
    $this->{cc}     = $cc;
    
    return $this;
}


sub reproduce
{   my $el = shift;

    join ' ' ,
    (   $el->{Name} ,
        map { "$el->{Attributes}{$_}{Name}=\"$el->{Attributes}{$_}{Value}\"" }
            keys %{$el->{Attributes}}
    )
}

sub characters 
{
    my ($self, $el) = @_;
    my $cc = $self->{cc};
    $cc->{text}=\("$el->{Data}");
    $cc->aRun(0, length(${$cc->{text}}));
}

sub comment 
{
    my ($self, $el) = @_;
    my $cc = $self->{cc};
    $cc->{text}=\("<!--$el->{Data}\-->");
    $cc->aRun(0, length(${$cc->{text}}));
}

sub processing_instruction
{
    my ($self, $el) = @_;
    my $cc = $self->{cc};
    $cc->{text}=\("<\?$el->{Target} $el->{Data}\?>");
    $cc->aRun(0, length(${$cc->{text}}));
}
         
sub start_element 
{
    my ($self, $el) = @_;
    my $cc = $self->{cc};
    my $tag = "<".reproduce($el).">";
    my $keep= 1;

    my $name= $self->{xmlns}{"{$el->{NamespaceURI}}$el->{LocalName}"};

    if ($cc->{comps}{$name})
    {

        if ( my $parent = $cc->{comps}{$name}{parent})
        {   $cc->Middle([$name,$parent],0,$tag,'');
        }else
        {
            my %attributes =
            ( map  { @{$el->{Attributes}{$_}}{qw(LocalName Value)} }
              grep { $el->{Attributes}{$_}{NamespaceURI} eq '' }
              keys %{$el->{Attributes}}
              ,
              map  { @{$el->{Attributes}{$_}}{qw(LocalName Value)} }
              grep { $el->{Attributes}{$_}{NamespaceURI} 
                     eq $el->{NamespaceURI} 
                     and $el->{NamespaceURI} ne ''
                   }
              keys %{$el->{Attributes}}
            );

            $cc->Start(['Start',$name],0,$tag,'',\%attributes);
        }
        $keep=0 unless $cc->{comps}{$name}{keep};
    }

    if ($keep)
    {
        $cc->{text}=\$tag;
        $cc->aRun(0, length(${$cc->{text}}));
    }
}

sub end_element 
{
    my ($self, $el) = @_;
    my $cc = $self->{cc};
    my $tag="</".reproduce($el).">";

    my $tagit=0;
    my $keep =1;

    my $name= $self->{xmlns}{"{$el->{NamespaceURI}}$el->{LocalName}"};

    if ($cc->{comps}{$name})
    {   
        $tagit=1;
        $keep=0 unless $cc->{comps}{$name}{keep};
    }

    if ($keep)
    {
        $cc->{text}=\$tag;
        $cc->aRun(0, length(${$cc->{text}}));
    }

    if ($tagit)
    {   
        if (my $parent = $cc->{comps}{$name}{parent})
        {   $cc->Middle(["end_$name",$parent],0,$tag,'');
        }
        else
        {   $cc->End(['End',$name],0,$tag,'');
        }
    }

}

1;
__END__

=head1 SYNOPSIS

 use XML::SAX::ParserFactory;
 use Template::Averse::SAXHandler;
 use Template::Averse::Compiler;

 my $components = { read perldoc Template::Averse for the 
                    correct hash syntax.  
                  };
 -OR (for simple cases) -

 my $components = [ qw( local tag names to recognize ) ] ;


 my $compiler = new Template::Averse::Compiler($components,'top_name');

 my $handler = new Template::Averse::SAXHandler($compiler);

 my $p = XML::SAX::ParserFactory->parser(Handler => $handler);

 $p->parse_file(\*XML); # various methods for this, read the SAX
                        # documentation.

 my @code = $compiler->print_code();

=head1 DESCRIPTION

SAXHandler is an interface between the SAX parser and the Averse compiler.

=head1 METHODS

=over 4

=item new compiler translation

Create a new SAX Handler object.

=over 4

=item compiler 

required

An Averse compiler object.

=item translation 

optional - a hash reference

This provides an alternate set of translations to map between the Averse
component name and the xml tag name.  This overrides _all_ the
translations provided in the component definitions.  (i.e. the LocalName
and NamespaceURI items).

The hash will map the full uri and local tag name using the common
notation of {URI}localname, to the component name.

example

 my $components = { header_1 => { vars => '$title' }};

 my $translation =
 {  #   name of tag within xml         key in the hash

    '{http://www.w3.org/1999/xhtml}h1' => header_1
 };

=back 4

=back 4
 
=head1 SEE ALSO

perldoc Template::Averse

perldoc Template::Averse::Parser

