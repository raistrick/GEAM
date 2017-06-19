# perl script to cut down a sample list

print "FROM: $ARGV[0]\n";
print "TO: $ARGV[2]\n";
print "SET: $ARGV[1]\n";
print "DEL: $ARGV[3]\n";

# get withdrawn consent list
open (WDN, "</path/to/withdrawn/consent/list") or die "Could not open file for Withdrawn Consent List\n";
%wdns = ();
$h = <WDN>;
#print $h;
while (my $ln = <WDN>) {
  $ln =~ s/[\n\r]//g;
  if ($ln =~ m/\S/) {
      @cols = split(",", $ln);
      if ($cols[2] !~ m/[A-F]/) { $cols[2] = "M"; }
      $wdns{"$cols[1]$cols[2]"} = 1;
  }
}
close (WDN);

# convert and remove
open (FILE, "<$ARGV[0]") or die "CNOF samples input: $ARGV[0]\n";
$ARGV[1] =~ s/\/$//;
open (NEW, ">$ARGV[2]/data.set") or die "CNOF output - $!\n";
while (my $ln = <FILE>) {
  $flag = 0;
  foreach $key (keys %wdns) {
  if ($ln !~ m/$key/) {
    if ($ARGV[1] =~ m/mother/ && $ln =~ m/^[0-9]+M\s/) { # get if mother and requested
      $flag = 1;
    } elsif ($ARGV[1] =~ m/child/ && $ln =~ m/^[0-9]+[A-E]\s/) { # get if child and requested
      $flag = 1;
    } elsif ($ARGV[1] =~ m/all/ && $ln =~ m/^[0-9]+[A-Z]\s/) {
      $flag = 1;
    } else {
      print "REMOVED ($key): $ln";
    }
  }
  if ($flag == 1) { 
    $ln =~ s/[\n\r]//g;
    @cols = split($ARGV[3], $ln);
    print NEW "$cols[0] $cols[1]\n";
  }
}
close (NEW);
close (FILE);
