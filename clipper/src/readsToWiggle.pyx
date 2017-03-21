#import numpy

def readsToWiggle_pysam(reads, int tx_start, int tx_end, keepstrand, usePos, bint fracional_input):
    """
    
    converts pysam to a wiggle vector and some other stuff.
    
    input: (bamfile.fetch obj), tx_start, tx_end, strand, readPos, trim
    bamfile.fetch obj is from pysam.Samfile().fetch    
    tx_start is the genome coordinate of the start position of the window you care about
    tx_stop is genome stop
    strand is + or - to indicate which strand to create a wiggle from
    usePos is the position you'll be calling the read cover from one of: ["center", "start", "end"]
    fractional: boolean output fractional results instead of integers 
    
    output: wiggle array, jxns, positional counts (cover), read lengths, read locations
    
    """
    cdef int cur_pos
    cdef int read_start
    cdef int read_stop
    cdef int next_pos
    cdef float increment_value
    #cdef vector[int] vect

    gene_size = tx_end - tx_start + 1
    lengths = []

    #Something about numpy makes this break, the error is SystemError: Objects/listobject.c:169: bad argument to internal function
    #Probably better to use numpy arrays, but I don't know how much better
    
    wiggle = [0] * gene_size
    pos_counts = [0] * gene_size
    explicit_locations = [0] * (gene_size + 1)

    for x in xrange(len(explicit_locations)):
        explicit_locations[x] = set([])

    all_reads = set([])
    junctions = {}

    for read in reads:



        if read.is_reverse and keepstrand == "+":
            continue
        elif not read.is_reverse and keepstrand == "-":
            continue

        read_start = read.positions[0]
        read_stop = read.positions[-1]

        if read_start < tx_start or read_stop > tx_end:
            #this is a really funny bug from porting HTSeq, the old code used start_d, for directional
            #this lead to cases where a negative strand read could have a start_d > tx_start and a stop_d < tx_end
            #but if the starts and stops were swapped, the end would fall outside of the tx_end.
            #what I really want is just reads falling entirely inside the transcript, so they should be removed,
            #but because I'm currently trying to replicate functionality exactly I need to build in a really odd expection
            #to just add reads to my explicit location array, if they meet that criteria.
            if read.is_reverse:
                read_start_d = read.positions[-1]
                read_stop_d = read.positions[0]

                record_read = (read_start_d > tx_start) & (read_stop_d < tx_end)

                if record_read:
                    for cur_pos, cigop in zip(read.positions, get_full_length_cigar(read)):
                        if cur_pos > gene_size:
                            continue
                        if cigop == 0: #Exact matches only, doing this because it duplicates HTSeq behavior
                            explicit_locations[cur_pos - tx_start].add(read)


            continue
            
        read_len = len(read.positions)
        lengths.append(read_len)



        if usePos == "center":
            pos_counts[(((read_stop + read_start) / 2) - tx_start)] += 1
        elif usePos == "start":
            if keepstrand == "+":
                pos_counts[read_start - tx_start] += 1
            else: 
                pos_counts[read_stop - tx_start] += 1
        elif usePos == "end":
             if keepstrand == "-":
                pos_counts[read_start - tx_start] += 1
             else: 
                pos_counts[read_stop - tx_start] += 1
        
        all_reads.add((read_start, read_stop))
        
        increment_value = (1.0 / read_len) if fracional_input else 1.0

        cigops = list(get_full_length_cigar(read))
        if len(cigops) != len(read.positions):
            print "read not handled correctly, email developer"
            print read.qname

        #this is a shitty hack to duplicate a bug in HTSeq, eventually I'll want to remove this
        #when I don't care about exactly duplicating clipper functionality
        record_read = (read_start > tx_start) & (read_stop < tx_end)

        for cur_pos, next_pos, cigop in zip(read.positions, read.positions[1:], cigops):
            #if cur is not next to the next position than its a junction
            if cur_pos + 1 != next_pos:
                junction = (cur_pos, next_pos)
                if junction not in junctions:
                    junctions[junction] = 0
                junctions[junction] += 1
                
            wiggle[cur_pos - tx_start] += increment_value
            if cigop == 0 and record_read: #Exact matches only, doing this because it duplicates HTSeq behavior
                explicit_locations[cur_pos - tx_start].add(read)

        #needed to get last read counted
        wiggle[read.positions[-1] - tx_start] += increment_value
        if cigops[-1] == 0 and record_read:
            explicit_locations[read.positions[-1] - tx_start].add(read)

    return wiggle, junctions, pos_counts, lengths, all_reads, explicit_locations

def get_full_length_cigar(read):
    for t in read.cigartuples:
        value, times = t

        #value 3 is splice junction value 2 is deletion in read
        if value == 3 or value == 2 or value == 1:
            continue
        for x in xrange(times):
            yield value