package GeoHash;
use strict;
use warnings;
our $VERSION = '0.01';

use Exporter 'import';
our @EXPORT_OK   = qw( ADJ_TOP ADJ_RIGHT ADJ_LEFT ADJ_BOTTOM );
our %EXPORT_TAGS = (adjacent => \@EXPORT_OK);

BEGIN {
    my @classes = qw( Geo::Hash::XS Geo::Hash );
    if (my $backend = $ENV{PERL_GEOHASH_BACKEND}) {
        if ($backend eq 'Geo::Hash') {
            @classes = qw( GeoHash::backendPP );
        } elsif ($backend eq '+Geo::Hash') {
            @classes = qw( Geo::Hash );
        } else {
            @classes = ( $backend );
        }
    }

    local $@;
    my $class;
    for (@classes) {
        $class = $_;
        last if $class eq 'GeoHash::backendPP';
        eval "use $class";## no critic
        last unless $@;
    }
    die $@ if $@;

    sub backend_class { $class }

    no strict 'refs';
    *ADJ_RIGHT  = \&{"$class\::ADJ_RIGHT"};
    *ADJ_LEFT   = \&{"$class\::ADJ_LEFT"};
    *ADJ_TOP    = \&{"$class\::ADJ_TOP"};
    *ADJ_BOTTOM = \&{"$class\::ADJ_BOTTOM"};
}

sub new {
    my($class) = @_;
    my $backend = $class->backend_class->new;
    bless {
        backend => $backend,
    }, $class;
}

for my $method (qw/ encode decode decode_to_interval adjacent neighbors precision /) {
    my $code = sub {
        my $self = shift;
        $self->{backend}->$method(@_);
    };
    no strict 'refs';
    *{$method} = $code;
}

{
    package GeoHash::backendPP;
    use strict;
    use warnings;
    use parent 'Geo::Hash';
    use Carp;

    my @ENC = qw(
        0 1 2 3 4 5 6 7 8 9 b c d e f g h j k m n p q r s t u v w x y z
    );

    # https://github.com/yappo/Geo--Hash/tree/issue-60782
    use POSIX qw/ceil/;

    use constant LOG2_OF_10  => log(10)  / log(2);
    use constant LOG2_OF_180 => log(180) / log(2);
    use constant LOG2_OF_360 => log(360) / log(2);

    sub _num_of_decimal_places($) {## no critic
        my $n = shift;
        return 0 unless $n =~ s/.*\.//;
        return length $n;
    }

    sub _length_for_bits($$) {## no critic
        my ( $bits, $is_lat ) = @_;
        my $q = int( $bits / 5 );
        my $r = $bits % 5;
        if ( $r == 0 ) {
            return $q * 2;
        }
        elsif ( $r <= ( $is_lat ? 2 : 3 ) ) {
            return $q * 2 + 1;
        }
        else {
            return $q * 2 + 2;
        }
    }

    sub precision {
        my ( $self, $lat, $lon ) = @_;
        my $lat_bit = ceil( _num_of_decimal_places( $lat ) * LOG2_OF_10 + LOG2_OF_180 );
        my $lon_bit = ceil( _num_of_decimal_places( $lon ) * LOG2_OF_10 + LOG2_OF_360 );
        my $lat_len = _length_for_bits( $lat_bit, 1 );
        my $lot_len = _length_for_bits( $lon_bit, 0 );
        return $lat_len > $lot_len ? $lat_len : $lot_len;
    }

    # https://github.com/yappo/Geo--Hash/tree/feature-geo_hash_xs
    use constant ADJ_RIGHT  => 0;
    use constant ADJ_LEFT   => 1;
    use constant ADJ_TOP    => 2;
    use constant ADJ_BOTTOM => 3;

    my @NEIGHBORS = (
        [ "bc01fg45238967deuvhjyznpkmstqrwx", "p0r21436x8zb9dcf5h7kjnmqesgutwvy" ],
        [ "238967debc01fg45kmstqrwxuvhjyznp", "14365h7k9dcfesgujnmqp0r2twvyx8zb" ],
        [ "p0r21436x8zb9dcf5h7kjnmqesgutwvy", "bc01fg45238967deuvhjyznpkmstqrwx" ],
        [ "14365h7k9dcfesgujnmqp0r2twvyx8zb", "238967debc01fg45kmstqrwxuvhjyznp" ]
    );

    my @BORDERS = (
        [ "bcfguvyz", "prxz" ],
        [ "0145hjnp", "028b" ],
        [ "prxz", "bcfguvyz" ],
        [ "028b", "0145hjnp" ]
    );

    sub adjacent {
        my ( $self, $hash, $where ) = @_;
        my $hash_len = length $hash;

        croak "PANIC: hash too short!"
            unless $hash_len >= 1;

        my $base;
        my $last_char;
        my $type = $hash_len % 2;

        if ( $hash_len == 1 ) {
            $base      = '';
            $last_char = $hash;
        }
        else {
            ( $base, $last_char ) = $hash =~ /^(.+)(.)$/;
            if ($BORDERS[$where][$type] =~ /$last_char/) {
                my $tmp = $self->adjacent($base, $where);
                substr($base, 0, length($tmp)) = $tmp;
            }
        }
        return $base . $ENC[ index($NEIGHBORS[$where][$type], $last_char) ];
    }

    sub neighbors {
        my ( $self, $hash, $around, $offset ) = @_;
        $around ||= 1;
        $offset ||= 0;

        my $last_hash = $hash;
        my $i = 1;
        while ( $offset-- > 0 ) {
            my $top  = $self->adjacent( $last_hash, ADJ_TOP );
            my $left = $self->adjacent( $top, ADJ_LEFT );
            $last_hash = $left;
            $i++;
        }

        my @list;
        while ( $around-- > 0 ) {
            my $max = 2 * $i - 1;
            $last_hash = $self->adjacent( $last_hash, ADJ_TOP );
            push @list, $last_hash;

            for ( 0..( $max - 1 ) ) {
                $last_hash = $self->adjacent( $last_hash, ADJ_RIGHT );
                push @list, $last_hash;
            }

            for ( 0..$max ) {
                $last_hash = $self->adjacent( $last_hash, ADJ_BOTTOM );
                push @list, $last_hash;
            }

            for ( 0..$max ) {
                $last_hash = $self->adjacent( $last_hash, ADJ_LEFT );
                push @list, $last_hash;
            }

            for ( 0..$max ) {
                $last_hash = $self->adjacent( $last_hash, ADJ_TOP );
                push @list, $last_hash;
            }
            $i++;
        }

        return @list;
    }
}

1;
__END__

=head1 NAME

GeoHash - Geo::Hash* wrapper with any utils

=head1 SYNOPSIS

    use GeoHash;
    my $gh = Geo::Hash->new();
    my $hash = $gh->encode( $lat, $lon );  # default precision = 32
    my $hash = $gh->encode( $lat, $lon, $precision );
    my ($lat, $lon) = $gh->decode( $hash );

fource use pp

   BEGIN { $ENV{PERL_GEOHASH_BACKEND} = 'Geo::Hash' }
   use GeoHash;

fource use xs

   BEGIN { $ENV{PERL_GEOHASH_BACKEND} = 'Geo::Hash::XS' }
   use GeoHash;

=head1 DESCRIPTION

GeoHash is

=head1 METHODS

=head2 $gh = Geo::Hash::XS->new()

=head2 $hash = $gh->encode($lat, $lon[, $precision])

Encodes the given C<$lat> and C<$lon> to a geohash. If C<$precision> is not
given, automatically adjusts the precision according the the given C<$lat>
and C<$lon> values.

If you do not want GeoHash to spend time calculating this, explicitly
specify C<$precision>.

=head2 ($lat, $lon) = $gh->decode( $hash )

Decodes $hash to $lat and $lon

=head2 ($lat_range, $lon_range) = $gh->decode_to_interval( $hash )

Like C<decode()> but C<decode_to_interval()> decodes $hash to $lat_range and $lon_range. Each range is a reference to two element arrays which contains the upper and lower bounds.

=head2 $adjacent_hash = $gh->adjacent($hash, $where)

Returns the adjacent geohash. C<$where> denotes the direction, so if you
want the block to the right of C<$hash>, you say:

    use GeoHash qw(ADJ_RIGHT);

    my $gh = GeoHash->new();
    my $adjacent = $gh->adjacent( $hash, ADJ_RIGHT );

=head2 @list_of_geohashes = $gh->neighbors($hash, $around, $offset)

Returns the list of neighbors (the blocks surrounding $hash)

=head2 $precision = $gh->precision($lat, $lon)

Returns the apparent required precision to describe the given latitude and longitude.

=head2 @list_of_merged_geohashes = $gh->merge(@list_of_geohashes)

=head2 @list_of_geohashes = $gh->crash(@list_of_merged_geohashes)

=head1 CONSTANTS

=head2 ADJ_LEFT, ADJ_RIGHT, ADJ_TOP, ADJ_BOTTOM

Used to specify the direction in C<adjacent()>

=head1 AUTHOR

Kazuhiro Osawa E<lt>yappo {at} shibuya {dot} plE<gt>

=head1 SEE ALSO

L<Geo::Hash>, L<Geo::Hash::XS>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
