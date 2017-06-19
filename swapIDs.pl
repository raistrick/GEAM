# perl script to read through file in arg 1 and replace with CID file in arg 2
# delimiter in main file set in arg 3

print "Opening Collaborator ID (CID) file $ARGV[1]...\n";

%cid = ();
open (CID, "<$ARGV[1]") or die "CID error: $!\n";
$h = <CID>;
while (my $ln = <CID>) {
  $ln =~ s/[\n\r]//g;
  @cols = split(",", $ln);
  $cid{$cols[0]} = $cols[1];
}
close (CID);

# random for removed
$x = 1 + int(rand(100 - 1));
%seen = ();
%seenaln = ();

open (FILE, "<$ARGV[0]");
open (NEW, ">$ARGV[0].new");
while (my $ln = <FILE>) {
  $ln =~ s/[\n\r]//g;
  @cols = split("$ARGV[2]", $ln);

  # for each column
  for ($i=0; $i<@cols; $i++) {
    # if column matches ALNQLET (bespoke format for IDs in study)
    if ($cols[$i] =~ m/^[0-9]{5}[A-Z]$/) {
      # get ALN string
      $aln = substr($cols[$i], 0, 5);

      # if missing aln seen, get random val
      # else loop  until new random number found
      if (defined $seenaln{$aln}) { 
        $x = $seen{$aln}; 
        print "$aln seen as missing before, REM_$x\n"; exit;
      } else {
        while (defined $seen{$x}) { $x = 1 + int(rand(100 - 1)); }
      }

      # get new value, as random initially
      $new = "REM_$x";
      if (defined $cid{$aln}) {
        $new = $cid{$aln};
      } else {
        print "Warning: $aln not found\n"; exit;
        $seen{$x} = 1;
        $seenaln{$aln} = $x;
      }
    
      $cols[$i] =~ s/$aln/$new/;
    }
  }
  print NEW join("$ARGV[2]", @cols)."\n";
}
close (NEW);
close (FILE);

$moved = `mv $ARGV[0].new $ARGV[0]`;
if ($moved ne "") {
  print "Error: $moved\n";
}
