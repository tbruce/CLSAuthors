SCHOLARSHIP_ENDPOINT='http://174.129.152.17:8080/openrdf-sesame/repositories/tomscholar2'
JSON_ROOT_DIRECTORY='/var/data/json'

require 'rdf'
include RDF
require 'sparql'
#require 'sparql/client'
require 'linkeddata'

class ScholarJsonFactory
  def initialize
      @sparql = SPARQL::Client.new(SCHOLARSHIP_ENDPOINT)
      check_needed_dirs
  end
  def run
    ['CFR','USC','SCOTUS'].each do |type|
      uris = get_uri_list(type)
      uris.each do |uri|
         do_item(uri, type)
      end
    end
  end
  # grabs list of all cited-to URIs for CFR, US Code, Supreme Court
  def get_uri_list(type)
    uri_list = Array.new
     case type
       when 'CFR'
         predicate = '<http://liicornell.org/liischolar/refCFR>'
       when 'USC'
         predicate = '<http://liicornell.org/liischolar/refUSCode>'
       when 'SCOTUS'
         predicate = '<http://liicornell.org/liischolar/refSCOTUS>'
     end
    # query
    result = @sparql.query("SELECT DISTINCT ?o WHERE {?s #{predicate} ?o .}")
    result.each do |item|
     o = item[:o].to_s
     uri_list.push(o)
    end
    return uri_list
  end
  def do_item(uri, type)
     # construct the path, filename
    rootdir = ''
    myprop = ''
    myuri = ''

    case type
      when 'CFR'
        rootdir = JSON_ROOT_DIRECTORY + '/cfr'
        uristart = 'cfr:'
        urimid = '_CFR_'
        myprop = 'refCFR'
      when 'USC'
        rootdir = JSON_ROOT_DIRECTORY + '/uscode'
        uristart = 'usc:'
        urimid = '_USC_'
        myprop = 'refUSCode'
      when 'SCOTUS'
        rootdir = JSON_ROOT_DIRECTORY + '/supremecourt'
        uristart = 'scotus:'
        urimid = '_US_'
        myprop = 'refSCOTUS'
    end
     parts = uri.split('/')
     cite = parts.pop

     vol_or_title, midbit, pg_or_section =  cite.split('_')

     parentdir = rootdir + '/' + vol_or_title
     mydir = parentdir + '/' + pg_or_section
     Dir.mkdir(parentdir) unless Dir.exist?(parentdir)
     Dir.mkdir(mydir) unless Dir.exist?(mydir)

     myuri = uristart + vol_or_title + urimid + pg_or_section

     # get the JSON
     q = <<EOQ
     PREFIX rdfs:<http://www.w3.org/2000/01/rdf-schema#>
     PREFIX owl:<http://www.w3.org/2002/07/owl#>
     PREFIX xsd:<http://www.w3.org/2001/XMLSchema#>
     PREFIX rdf:<http://www.w3.org/1999/02/22-rdf-syntax-ns#>
     PREFIX xml:<http://www.w3.org/XML/1998/namespace>
     PREFIX skos:<http://www.w3.org/2004/02/skos/core#>
     PREFIX dct:<http://purl.org/dc/terms/>
     PREFIX usc:<http://liicornell.org/liiuscode/>
     PREFIX foaf: <http://xmlns.com/foaf/0.1/>
     PREFIX cfr:<http://liicornell.org/liicfr/>
     PREFIX scotus:<http://liicornell.org/liiscotus/>
     PREFIX scholar:<http://liicornell.org/liischolar/>

     SELECT DISTINCT ?title  ?authname ?link ?biolink
     WHERE {
       ?work dct:title ?title .
       ?work scholar:abstractPage ?link .
       ?author foaf:name ?authname .
       ?author scholar:institutionBio ?biolink .
       ?work dct:contributor ?author
       FILTER regex (str(?author),'scholars','i') .
           {
               SELECT ?work
       WHERE { ?work scholar:
EOQ
       q.rstrip!  # looks like heredoc adds whitespace in ruby
       q = q + myprop
       q = q + " "
       q = q + myuri
       q = q + " . } } }"
    begin
      results = @sparql.query(q)
    rescue Exception => e
      puts "for URI #{uri} :"
      puts e.message
      puts e.backtrace.inspect
      return
    end

     # write
     f = File.new(mydir+"/scholarship.json","w")
     f << results.to_json
     f.close
  end

  # make sure we have the directories we need

  def check_needed_dirs
    Dir.mkdir(JSON_ROOT_DIRECTORY) unless Dir.exist?(JSON_ROOT_DIRECTORY)
    Dir.mkdir(JSON_ROOT_DIRECTORY + '/cfr') unless Dir.exist?(JSON_ROOT_DIRECTORY + '/cfr')
    Dir.mkdir(JSON_ROOT_DIRECTORY + '/uscode') unless Dir.exist?(JSON_ROOT_DIRECTORY + '/uscode')
    Dir.mkdir(JSON_ROOT_DIRECTORY + '/supremecourt') unless Dir.exist?(JSON_ROOT_DIRECTORY + '/supremecourt')
  end

end

factory = ScholarJsonFactory.new()
factory.run