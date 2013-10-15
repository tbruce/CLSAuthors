require 'csv'
require 'rdf'
include RDF

JELS_CSVFILE = '/home/tom/Dropbox/Scholarship/JELclassification.csv'
JELS_CLS_PREFIX = 'http://liicornell.org/jel/'

class JELSKOSifier
  # To change this template use File | Settings | File Templates.
  def initialize
    @jelterms = Array.new()
    @terms_hash = Hash.new()

    CSV.foreach(JELS_CSVFILE) do |row|
      toim, desc = row
      @jelterms.push(toim)
      @terms_hash[toim] = desc
    end
    @terms_hash.shift
    @jelterms.pop()
  end
  def skosify_terms
    RDF::Writer.for(:ntriples).new($stdout) do |writer|
      writer << RDF::Graph.new do |graph|
        @terms_hash.keys.each do |cls|
          df = @terms_hash[cls]
          graph << [RDF::URI(JELS_CLS_PREFIX + cls), SKOS.prefLabel, df]
        end
      end
    end
  end

  def do_narrower
    RDF::Writer.for(:ntriples).new($stdout) do |writer|
      writer << RDF::Graph.new do |graph|
        #iterate through the list of keys
        @jelterms.each do |term|
          #everything that begins with X is a narrower term for X00
          t = term[0]
          graph << [RDF::URI(JELS_CLS_PREFIX + t + '00'), SKOS.narrower, RDF::URI(JELS_CLS_PREFIX + term)] if term[1..2] != '00'
          # if it has a zero in the second place, skip to the next
          next if term[1] == '0'
          #everything that does not end in zero is a narrower term for a string that has the same first two characters and
          # *does* end in zero
          brd = term[0..1] + '0'
          graph << [RDF::URI(JELS_CLS_PREFIX + brd), SKOS.narrower, RDF::URI(JELS_CLS_PREFIX + term)]
        end

      end
    end
  end
end

jsk = JELSKOSifier.new()
jsk.skosify_terms
jsk.do_narrower