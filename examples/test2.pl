sub _candidate_files {
    my $parms = shift;
    my $dir = shift;
    my $dh;
    if ( !opendir $dh, $dir ) {
        $parms->{error_handler}->( "$dir: $!" );
        return;
    }
    my @newfiles;
    my $descend_filter = $parms->{descend_filter};
    my $follow_symlinks = $parms->{follow_symlinks};
    my $sort_sub = $parms->{sort_files};
    while ( defined ( my $file = readdir $dh ) ) {
        next if $skip_dirs{$file};
        my $has_stat;
        my $fullpath = File::Spec->catdir( $dir, $file );
        if ( !$follow_symlinks ) {
            next if -l $fullpath;
            $has_stat = 1;
        }
        if ( $descend_filter ) {
            if ( $has_stat ? (-d _) : (-d $fullpath) ) {
                local $File::Next::dir = $fullpath;
                local $_ = $file;
                next if not $descend_filter->();
            }
        }
        if ( $sort_sub ) {
            push( @newfiles, [ $dir, $file, $fullpath ] );
        }
        else {
            push( @newfiles, $dir, $file, $fullpath );
        }
    }
    closedir $dh;
    if ( $sort_sub ) {
        return map { @{$_} } sort $sort_sub @newfiles;
    }
    return @newfiles;
}
print STDERR "THIS IS A BUG\n";
1;
