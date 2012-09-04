#         FILE: my-dic.pl
#       AUTHOR: jaemin.choi (), skyloader@gmail.com
#      CREATED: 2012/04/17 22시 07분 03초
#===============================================================================

use 5.014;
use utf8;
use strict;
use warnings;

use Data::Dumper;
use Encode qw( decode_utf8 encode_utf8 );
use HTML::TreeBuilder;
use LWP::UserAgent;
use Text::Wrap;
use YAML;

binmode STDOUT, ":utf8";
#binmode STDIN, ":utf8";
my $ua = LWP::UserAgent->new;
$ua->timeout(10);
$ua->env_proxy;

my ($dic_type, $query, $tree) = ();
my $cache_name = q{cache.data};

#if (@ARGV == 2 && $ARGV[0] =~ /(ek|ke)/) {
if ($ARGV[0] =~ /(ek|ke)/) {
#    ($dic_type, $query) = @ARGV;
    ($dic_type, $query) = (split /\s+/, "@ARGV", 2);
    $tree = load_cache($cache_name) if (-e $cache_name);
#    print $tree->as_HTML, "\n";
    call_dic($dic_type, $query, $tree);
    exit;
};

$tree = load_cache($cache_name) if (-e $cache_name);
while ( 1 ) {
    my $line = <STDIN>;
    last unless $line;
    chomp $line;
    ($dic_type, $query) = (split /\s+/, $line, 2);
    my $is_cmd; 
    $is_cmd = check_cmd($dic_type, $query);
    next if $is_cmd eq 'FALSE';
    call_dic($dic_type, $query, $tree);
}

sub check_cmd {
    my ($dic_type, $query) = @_;
    return 'FALSE' unless ($dic_type =~ /(ek|ke)/);
    return 'FALSE' unless $query;
    return 'TRUE';
}

sub load_cache {
    my $filename = shift;

    open my $fh, "<:encoding(UTF-8)", $filename if -e $filename;
    my $tree = HTML::TreeBuilder->new(
        implicit_tags => 0,
    );
    $tree->parse_file($fh);
    close $fh;

    return $tree;
}

sub call_dic {
    my ($dic_type, $query, $tree) = @_;
    
    my %word_data;
    my $word;
    my $find;
#    $find = $tree->find_by_attribute('id', qr{\b$query\b});

    my $utf8_query = decode_utf8($query);
    $find = $tree->look_down('id', $utf8_query);
    undef $find unless $utf8_query eq $find->attr('id');

    # data structure 
    # --------------
    # $word_data = { 
    #                'query' => [ # alt - number
    #                             {
    #                               noun => [ # type - [noun, verb .. etc.]
    #                                         'meaning_noun0', # meaning - string
    #                                         'meaning_noun1',
    #                                       ],
    #                               verb => [ 
    #                                         'meaning_verb0',
    #                                         'meaning_verb1',
    #                                       ],
    #                             },
    #                             {
    #                               verb => [
    #                                         'meaning_verb0',
    #                                       ],
    #                             },
    #                           ],
    #              },
    #                                 
    if ($find) {
        my @node_alts = $find->find_by_tag_name('alt');
        my $alt_idx = 0;
        for my $alt (@node_alts) {
            my @node_types = $alt->find_by_tag_name('type');
            for my $type (@node_types) {
                my $name;
                $name = $type->attr_get_i('name') ? $type->attr_get_i('name') : 'NONE'; 
                for my $mean ( $type->look_down('no', qr/\d+/) ) {
                    push @{$word_data{$query}[$alt_idx]{$name}}, $mean->as_text;
                }
            }
            $alt_idx ++;
        }
        print_screen(\%word_data);
    }
    else {
        my $result = ekke_search($ua, $query);
        if ( ( ref $result ) =~ /^HASH/ ) {
            print_screen($result);
            print_cache($result);
        }
    }
}

sub print_cache_xx {
#    my %word_data = %{shift};                   # is this possible?

}

sub print_cache {
    my $word_ref = shift;
    
    open my $fh, ">>", 'cache.data';
    binmode $fh, ":utf8";
    for my $word ( sort keys %$word_ref ) {
        print $fh qq(<word id=") . decode_utf8($word) . qq(">\n);
        for my $alt_idx ( 0 .. $#{$word_ref->{$word}} ) {
            print $fh qq{ } x 2, qq{<alt no="$alt_idx">\n};
            for my $type ( sort keys $word_ref->{$word}[$alt_idx] ) {
                print $fh qq{ } x 4, qq{<type name="$type">\n};
                for my $mean_idx ( 0 .. $#{$word_ref->{$word}[$alt_idx]{$type}} ) {
                    print $fh qq{ } x 6, qq{<meaning no="$mean_idx">}, 
                        $word_ref->{$word}[$alt_idx]{$type}[$mean_idx],
                        qq{</meaning>\n};
                }
                print $fh qq{ } x 4, qq{</type>\n};
            }
            print $fh qq{ } x 2, qq{</alt>\n};
        }
        print $fh qq{</word>\n};
    }
}

sub print_screen {
    my $word_ref = shift;

    for my $word ( sort keys %$word_ref ) {
        my $alt_idx = 1;
        say decode_utf8($word); 
        for my $alt_h ( @{$word_ref->{$word}} ) {
            say "Mean " . decode_utf8($alt_idx);
            for my $type (keys %$alt_h) {
                say q{ } x 2 . decode_utf8($type) . ":";
                my $mean_idx = 1;
                for my $mean ( @{$alt_h->{$type}} ) {
                    say q{ } x 4 . $mean_idx . ', ' . decode_utf8($mean);
                    $mean_idx++;
                }
            }
            $alt_idx ++;
        }
    }
}

sub ekke_search {
    my ($ua, $query, $url) = @_;

    my $res;
    if ($url) {
        $res = $ua->get("http://endic.naver.com/$url");
    }
    else {
        $res = $ua->get("http://endic.naver.com/popManager.nhn?m=search&searchOption=&query=$query");
    }
    
    my $tree = HTML::TreeBuilder->new();
    $tree->parse( $res->decoded_content );
    $tree->eof();

    my @node;
    my $is_single_mean;
    $is_single_mean = $tree->look_down( _tag => 'div', class => qr/word_view/ );
    my @is_multi_mean; 
    @is_multi_mean  = $tree->look_down( _tag => 'div', class => qr/word_num/ ) unless $is_single_mean;
    if ($is_single_mean) {
        return get_single_meaning($tree, $query);
    }
    elsif ($#is_multi_mean > 0) {
        my $url_pair;
        $url_pair = catch_multi_word($tree, $query);
        my %result;
        my $alt_idx = 0;
#        while ( my ($key, $url) = each %$url_pair) {
        for my $key ( sort keys %$url_pair ) {
            my $url = $url_pair->{$key};
#            $alt_idx ++ and $key =~ s/\b($query)\d+/$1/ if $key =~ /\b$query\d+/; #  This code doesn't work when I searched 'tag'. It didn't get tag1.
#            if ($key =~ /\b$query\d+/) {
#                $alt_idx ++;
#                $key =~ s/\b($query)\d+/$1/;
#            }
            if ($key =~ /\d+$/) {
                $alt_idx ++;
                $key =~ s/\d+$//;
            }
            $result{$key}[$alt_idx] = ekke_search($ua, $key, $url)->{$key}[0];
#            $result{$key}[$alt_idx] = ekke_search($ua, $key, $url)->{$key}[0] if     $key eq qq{$query};
#            $result{$key}           = ekke_search($ua, $key, $url)->{$key}    unless $key eq qq{$query};
        }
        return \%result;
    }
    else {

    }
}

sub catch_multi_word {
	my ( $tree, $query ) = @_;

    # find url
    my $words_page;
    $words_page = $tree->look_down( 
        _tag  => 'div', 
        class => qr/word_num\s*$/,
    );

    my $multi_words;
    $multi_words = $words_page->look_down(
        _tag  => 'dl',
        class => 'list_e2',
    );

    my @each_word;
    @each_word   = $multi_words->look_down( 
        _tag  => 'dt',
    );

    my %url_pair;
    for my $elem (@each_word) {
        $elem = $elem->look_down( 
            _tag  => 'span',
            class => 'fnt_e30',
        );
        $elem = $elem->look_down( _tag => 'a' );
        
        my $word_key = $elem->as_text;
        $url_pair{$word_key} = ${$elem->extract_links('a')}[0][0];
    }

    return \%url_pair;
}

sub get_single_meaning {
	my ($tree, $query, $alt_idx) = @_;

    $alt_idx = 0 unless $alt_idx;

	my @nodes = $tree->find_by_tag_name('dt');
	my %word;
    # The keys which I want to find
	my %info_attr = (
		part_of_speech  => { _tag => 'span', class => qr/\bfnt_syn\b/   },
		mean_top        => { _tag => 'dl',   class => qr/\blist_a3\b/   },
		type_top        => { _tag => 'h3',   class => qr/\bdic_tit6\b/  },
        meaning	        => { _tag => 'dt',   class => qr/\bmean_on\b/   },
        sub_meaning	    => { _tag => 'dt',   calss => qr/\bmean_on\b/   },
        phrase          => { _tag => 'dt',   class => qr/\balign_px\b/  },
	);

    for my $node (@nodes) {
        my $cont;
        $cont = $node->look_down( %{$info_attr{meaning}} );
        $cont = $node->look_down( %{$info_attr{sub_meaning}} ) unless $cont;
        $cont = $node->look_down( %{$info_attr{phrase}} ) unless $cont;
        next unless $cont;

        my $type;
        $type = $node->look_up  ( %{$info_attr{mean_top}} );
        $type = $type->left     ( %{$info_attr{type_top}} )       if $type;
        $type = $type->look_down( %{$info_attr{part_of_speech}} ) if $type;

        $type = $type ? $type->as_text() : q{};

        my $meaning = decode_utf8( $cont->as_text( skip_spans => 1 ) );
        $meaning =~ s/^\d*\.*//;
        push @{$word{$query}[$alt_idx]{$type}}, $meaning;
    }
    return \%word if %word;
    return "$query : Not proper word, search another one" unless %word;
}
