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
          next unless term =~ /[1-9]+/
          # everything that is broader than me has a zero in the last place where I have an integer, and is like me up to that point
          broader_term = term.dup
          lasti = term.rindex(/[1-9]/)
          broader_term[lasti] = "0"
          graph << [RDF::URI(JELS_CLS_PREFIX + broader_term), SKOS.narrower, RDF::URI(JELS_CLS_PREFIX + term)]
        end
      end
    end
  end
end

jsk = JELSKOSifier.new()
jsk.skosify_terms
jsk.do_narrower