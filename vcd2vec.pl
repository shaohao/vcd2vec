#!/usr/bin/perl -w

use strict;
use warnings;

#------------------------------------------------------------------------------

my %time_precision = (
     s => 1e15,
    ms => 1e12,
    us => 1e9,
    ns => 1e6,
    ps => 1e3,
    fs => 1e0,
);

my %header_commands = (
    comment => 1, date => 1, timescale => 1, scope => 1, var => 1, upscope => 1,
    enddefinitions => 1,
);

my %dump_commands = (
    dumpvars => 1,
    dumpon => 1,
    dumpoff => 1,
    dumpall => 1,
);

sub get_time_fs_from_string
{
    my $ts_str = shift;
    $ts_str =~ /(\d+)\s*([munpf]?s)/;
    return $1 * $time_precision{$2};
}

sub format_timestamp_from_fs
{
    my ($fs, $unit) = @_;
    return $fs / $time_precision{$unit};
}

#------------------------------------------------------------------------------

my @definitions = ();
my %dumpings = ();
my %variables = (); # indexed with id_code
my %ref_names = (); # indexed with id_code

my $buffer_line = q{};
my $in_dumping = 0;
my $in_comment = 0;
my $cmd_name = q{};
my $timescale = 0;
my $cur_time = -1;

open my $vcdfh, '<:encoding(UTF-8)', "$ARGV[0]" or die "Failed to open vcd file!\n";
while (read $vcdfh, my $c, 1) {
    if ($c !~ /\s/) {
        $buffer_line .= $c;
        next;
    }

    # Skip unused spaces
    next if (!$buffer_line);

    # Header
    if (!$in_dumping) {
        # $comment allow spaces
        if ($in_comment) {
            if ($buffer_line =~ /(.*)\$end$/s) {
                $in_comment = 0;
            }
            else {
                $buffer_line .= $c;
                next;
            }
        }

        if ($buffer_line =~ /.*\$(\w+)$/s and exists($header_commands{$1})) {
            $cmd_name = $1;
            $buffer_line = q{};
            if ($cmd_name eq 'comment') {
                $in_comment = 1;
            }
        }
        elsif ($cmd_name and $buffer_line =~ /(.*)\$end$/s) {
            push @definitions, { name => $cmd_name, content => $1 };
            $buffer_line = q{};
            if ($cmd_name eq 'enddefinitions') {
                &process_definitions;
                $in_dumping = 1;
            }
        }
        else {
            $buffer_line .= $c;
        }
    }
    # Dumping
    else {
        if ($buffer_line =~ /.*#(\d+)$/s) {
            $cur_time = $1 * $timescale;
            $dumpings{$cur_time} = {};
            $buffer_line = q{};
        }
        # TODO: NOT SUPPORT $dump* commands in dump phase
        elsif ($buffer_line =~ /^\$(\w+)$/s and exists($dump_commands{$1})) {
            $buffer_line = q{};
        }
        elsif ($buffer_line =~ /(.*)\$end$/s) {
            $buffer_line = q{};
        }
        elsif ($buffer_line =~ /^([01xzXZ])(\S+)|b([01xzXZ])\s+(\S+)$/) {
            $dumpings{$cur_time}->{$ref_names{$2}} = $1;
            $buffer_line = q{};
        }
        else {
            $buffer_line .= $c;
        }
    }
}
close $vcdfh;


sub process_definitions
{
    my $process_timescale = sub {
        my $item = shift;
        $item->{content} =~ /\s*(\d+)\s*([munpf]?s)\s*/s;
        $timescale = $time_precision{$2} * $1;
        $item->{content} = $timescale;
    };

    my $process_var = sub {
        my $item = shift;
        $item->{content} =~ /\s*(\w+)\s+(\d+)\s+(\S+)\s+(.*\S)\s*$/s;
        my $var = {
            var_type => $1,
            width => $2,
            id_code => $3,
            ref_name => $4,
        };
        $item->{content} = $var;
        $variables{$4} = $var;
        $ref_names{$3} = $4;
    };

    my $process_date = sub {
        my $item = shift;
        $item->{content} =~ s/\s*(.*\S)\s*$/$1/s;
    };

    for my $cmd (@definitions) {
        if ($cmd->{name} eq 'timescale') {
            &$process_timescale($cmd);
        }
        elsif ($cmd->{name} eq 'var') {
            &$process_var($cmd);
        }
        elsif ($cmd->{name} eq 'date') {
            &$process_date($cmd);
        }
        else {
            ; # Keep untouch
        }
    }
}

sub output_vec_file_header
{
    my $get_max = sub {
        my $max_value = shift;
        for (@_) {
            if (length($_) > length($max_value)) {
                $max_value = $_;
            }
        }
        return $max_value;
    };

    my @vars = sort(keys %variables);
    push @vars, '';
    my @name_in_chars = map { [split //] } @vars;
    my @transposed_names = ();
    my $max_rows = length(&$get_max(@vars));
    for (my $row = 0; $row <= $max_rows; ++$row) {
        my $line = join('',
            map { $row < scalar(@{$_}) ? $_->[$row] : ' ' } @name_in_chars,
        );
        push @transposed_names, $line;
        last if ($line !~ /\S/);
    }
    for (@transposed_names) {
        printf("%-13s %s\n", ';', $_);
    }
}

sub output_vec_file_body
{
    my $vec_clk = shift;

    my %sampled_values = ();
    my @vcd_times = sort(keys %dumpings);
    my ($vec_begin, $vec_end) = @vcd_times[0, $#vcd_times];
    my $p = $vec_begin;
    for (my $t = $vec_begin; $t <= $vec_end; $t += $vec_clk) {
        my @run_times = ();

        if ($t == $vec_begin) {
            @run_times = ($vec_begin);
        }
        else {
            @run_times = grep { $_ > $p and $_ <= $t; } @vcd_times;
        }
        for my $vcd_t (sort @run_times) {
            map {
                $sampled_values{$_} = $dumpings{$vcd_t}->{$_};
            } keys(%{$dumpings{$vcd_t}});
        }

        if (@run_times) {
            $p = $run_times[$#run_times];
        }

        printf("%13s %s\n",
            format_timestamp_from_fs($t, 'ns'),
            join('', values(%sampled_values)),
        );
    }
}

sub output_vec_file
{
    my $vec_clk = get_time_fs_from_string(shift);

    &output_vec_file_header;

    output_vec_file_body($vec_clk);
}

output_vec_file($ARGV[1]);

