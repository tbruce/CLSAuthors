
#-- This code makes some assumptions.
# -- SSRN URLs follow the templates described by the constants defined below
# -- There is no paging of the list of papers displayed by an author page -- that is, all of an author's papers are
#    listed on a single page, no matter how many there are.





# location of vocabularies that are not built into RDF::Writer
# these MUST have terminal slashes
# TODO: add JELS vocab

CLS_VOCABULARY='http://liicornell.org/liischolar/'
BIBO_VOCABULARY='http://purl.org/ontology/bibo/'

# SSRN-related config information

SSRN_ACCOUNT_NAME='trb2@cornell.edu'
SSRN_ACCOUNT_PWD='gruel07'
SSRN_LOGIN_AJAX = 'http://www.ssrn.com/loginAjaxHeader.cfm?login=true&username=' + SSRN_ACCOUNT_NAME + '&pass=' + SSRN_ACCOUNT_PWD
SSRN_AUTHOR_PREFIX='http://papers.ssrn.com/sol3/cf_dev/AbsByAuth.cfm?per_id='
SSRN_ABSTRACT_PREFIX='http://papers.ssrn.com/sol3/papers.cfm?abstract_id='
LII_SSRN_PAPER_URI_PREFIX='http://liicornell.org/ssrn/papers/'
LII_SSRN_AUTHOR_URI_PREFIX='http://liicornell.org/ssrn/authors/'
LII_JEL_URI_PREFIX='http://liicornell.org/jel/'
GPLUS_URI_PREFIX= 'https://plus.google.com/'
GSCHOLAR_URI_PREFIX='http://scholar.google.com/citations/hl=en&user='
OPENGRAPH_URI_PREFIX='http://graph.facebook.com/'

# Google spreadsheet used for configuration, and access info for it.
GOOGLE_UID='access.lii.cornell@gmail.com'
GOOGLE_PWD='crankmaster'
GOOGLE_SPREADSHEET_KEY='0AkDG2tEbluFPdFhIT09tdnpKWHV2dHRNQUVMLXBNSHc'

# services
CITATIONER_URI='http://mojo.law.cornell.edu/services/citationer/'
DBPEDIA_LOOKUP_PREFIX='http://lookup.dbpedia.org/api/search.asmx/KeywordSearch?QueryString='

require 'rubygems'
require 'net/http'
require 'simple-tidy'
require 'nokogiri'
require 'chronic'
require 'google_drive'
require 'tempfile'
require 'curb'
require 'watir-webdriver'
require 'headless'
require 'json'
require 'trollop'
require 'rdf'
include RDF
require 'rdf/ntriples'
require 'digest/md5'
require 'open-uri'


#-- class for representing/modeling some SSRN abstract pages

class SSRNAbstractPage
  attr_reader :paper_id,:author_id,:url,:keywords,:jelcodes,:coauthors,:abstract,:online_date,:pub_date,:doi,:title,:pdf_url

  def initialize(my_id, my_ssrn_author_id, my_cls_author_uri)
    @paper_id = my_id
    @ssrn_author_id = my_ssrn_author_id
    @cls_author_uri = my_cls_author_uri
    @url = SSRN_ABSTRACT_PREFIX + my_id
    @paper_URI = LII_SSRN_PAPER_URI_PREFIX + my_id
    @cls_ssrn_uri = LII_SSRN_AUTHOR_URI_PREFIX + my_ssrn_author_id


    @keywords = Array.new()
    @jelcodes = Array.new()
    @coauthors = Array.new()
    @abstract = nil
    @online_date = nil
    @pub_date = nil
    @doi = nil
    @title = nil
    @abstract_views = nil
    @paper_dls = nil
    @paper_citations = nil
    @paper_footnotes = nil
    @dl_rank = nil
    @extracted_citations = Array.new()

    @doc = nil

    begin
      uri = URI(@url)
      html = Net::HTTP.get(uri)
      unless html
        raise "Abstract page #{@url} unavailable"
      end
    rescue Exception => e
      puts e.message
      puts e.backtrace.inspect
    end
    # SSRN throws javascript in *before* the DOCTYPE declaration, believe it or not.  we don't need it, so...
    html.sub!(/^.*<!DOCTYPE/m,'<!DOCTYPE')
    # also, too, bogus <nobr> tags
    html.gsub!(/<\/*nobr>/m, '')

    clean_html = SimpleTidy.clean(html, :force_output => true)
    #clean_html = Nokogiri::HTML(html).to_html
    @doc = Nokogiri::HTML(clean_html)
  end

  #-- scrape the contents of the page
  def scrape
    return unless @doc
    scrape_metas
    scrape_stats
    scrape_authors
    scrape_abstract
    scrape_jelcodes
  end

  #-- get interesting metatag content
  def scrape_metas
      @title = @doc.at_xpath("//meta[@name='citation_title']")["content"]
      @online_date = @doc.at_xpath("//meta[@name='citation_online_date']")["content"]
      @pub_date = @doc.at_xpath("//meta[@name='citation_publication_date']")["content"]
      @doi = @doc.at_xpath("//meta[@name='citation_doi']")["content"]
      @doi = nil if @doi && @doi.empty?     #for unknown reasons this sometimes pulls a blank
      @keywords = @doc.at_xpath("//meta[@name='citation_keywords']")["content"].split(/,\s*/)
  end

  #-- get paper statistics
  def scrape_stats
    @labels = Array.new
    @stats = Array.new
    @doc.css("span.statisticsText").each do |label|
      @labels.push(label.inner_text())
    end
    idx = 0
    @doc.css("span.statNumber").each do |stat|
      num = stat.inner_text().gsub!(/[^0-9]/,'')
      @abstract_views = num if @labels[idx] =~ /Views/
      @paper_dls = num if @labels[idx] =~ /Downloads/
      @paper_citations = num if @labels[idx] =~ /Citations/
      @paper_footnotes = num if @labels[idx] =~ /Footnotes/
      @dl_rank = num if @labels[idx] =~ /Rank/
      idx = idx+1
    end
  end

  #-- get SSRN IDs of coauthors
  def scrape_authors
    @doc.xpath("//center/font/a[@title='View other papers by this author']").each do |link|
      auth_id =  /per_id=([0-9]+)/.match(link['href'])[1]
       @coauthors.push(auth_id) unless auth_id.eql?(@ssrn_author_id)
    end
  end

  def scrape_abstract
      elem = @doc.at_xpath("//div/div/div/font")
      return unless elem
      @abstract = elem.inner_text()
  end

  def scrape_jelcodes
    @doc.xpath("//div/div/div/p/font").each do |chunk|
      stuff = /JEL\s*Classification:\s*((([A-Z][0-9]+),*\s*)+)/.match(chunk.inner_text())
      if stuff
        @jelcodes = stuff[1].split(/,\s*/)
      end
    end
  end

  #-- create triples for everything we know about the paper
  def create_triples
    clsauthor = RDF::Vocabulary.new(CLS_VOCABULARY)
    bibo = RDF::Vocabulary.new(BIBO_VOCABULARY)
    myuri = RDF::URI(@paper_URI)
    RDF::Writer.for(:ntriples).new() do |writer|
      writer << RDF::Graph.new do |graph|
        graph << [myuri, DC.contributor, RDF::URI(@cls_author_uri)]
        graph << [myuri,RDF.type,bibo.Article]
        graph << [myuri,clsauthor.abstractPage,@url]
        graph << [myuri,DC.abstract,@abstract] if @abstract
        graph << [myuri,clsauthor.ssrnOnlineDate,@online_date] if @online_date
        graph << [myuri,clsauthor.ssrnPubDate,@pub_date] if @pub_date
        graph << [myuri,bibo.doi,@doi] if @doi
        graph << [myuri,DC.title,@title] if @title
        graph << [myuri,clsauthor.ssrnAbsViewCount,@abstract_views] if @abstract_views
        graph << [myuri,clsauthor.ssrnDLCount, @paper_dls] if @paper_dls
        graph << [myuri,clsauthor.ssrnCitationCount,@paper_citations] if @paper_citations
        graph << [myuri,clsauthor.ssrnFNCount,@paper_citations] if @paper_citations
        graph << [myuri, clsauthor.ssrnDLRank,@dl_rank] if @dl_rank
        @keywords.each do |subj|
          # normalize to lowercase
          subj.downcase!
          graph << [myuri,DC.subject, subj]
        end
        @jelcodes.each do |jel|
          graph << [RDF::URI(LII_JEL_URI_PREFIX + jel), RDF.type, clsauthor.JelClass ]
          graph << [myuri,clsauthor.jelClass, RDF::URI(LII_JEL_URI_PREFIX + jel)]
        end
        @coauthors.each do |scribbler|
          scribURI = RDF::URI(LII_SSRN_AUTHOR_URI_PREFIX + scribbler)
          graph << [scribURI, RDF.type, clsauthor.SSRNAuthor ]
          graph << [myuri, DC.contributor, scribURI]
          # stick in name information, just to be informative
          coauthpage = SSRNAuthorPage.new(scribbler,scribURI)
          coauthpage.scrape
          graph << [scribURI, FOAF.givenName, coauthpage.firstName]
          graph << [scribURI, FOAF.familyName, coauthpage.lastName]
        end
      end
    end
  end

  def extract_paper_citations(b,stashdir)
    b.goto @url
    # grab the PDF file
    begin
      b.link(:class,"downloadBt").click
    rescue StandardError
      return
    end
    # wait for DL to start
    while Dir.entries("#{stashdir}").length < 3
      sleep(1)
    end
    # wait for DL to complete
    myfile = Dir.entries("#{stashdir}").grep(/^SSRN/).first()
    while  File.exist?("#{stashdir}/#{myfile}.part")
      sleep(1)
    end
    # send the file to citationer
    c = Curl::Easy.new(CITATIONER_URI)
    c.multipart_form_post = true
    begin
      c.http_post(Curl::PostField.file('files',"#{stashdir}/#{myfile}"))
    rescue StandardError
      return
    end
    cite_json = c.body_str

    # kill the file and the directory
    File.unlink("#{stashdir}/#{myfile}") if File.exists?("#{stashdir}/#{myfile}")

    # see if the conversion ran right.  usual problem is PHP uploading error.
    jary = JSON.parse(cite_json)

  return if jary.empty?     # got nothing
  return if jary.first()[1].empty?       # got response with key but no value
  unless jary[myfile].nil?
    unless jary[myfile]['error'].nil?
      $stderr.puts "File #{myfile} throws error " + jary[myfile]['error']['type'] + " with message " + jary[myfile]['error']['emsg']
      return
    end
  end


    # process json from citationer
    create_citation_triples(cite_json)
  end

  # creates citation triples given json output from citationer
  # this creates triples using the following properties.
  # These take LII-minted URIs:
  # refCFR
  # refPopName
  # refUSCode
  # refSCOTUS
  # This takes a dbPedia URI
  # refDBPedia (based on popular name of act, and maybe on citation)
  # These take URLs for which there are no URIs
  # citedPage

  def create_citation_triples(cite_json)
    clsauthor = RDF::Vocabulary.new(CLS_VOCABULARY)
    puri = RDF::URI(@paper_URI)
    RDF::Writer.for(:ntriples).new($stdout) do |writer|
      writer << RDF::Graph.new do |graph|
        key, ary = JSON.parse(cite_json).first()
        # TODO: add logging for empty ary element (paper url)
        # TODO: add error handling/logging for ary that is an error hash with 3 elements (JSON docs?)
        ary.each do |mention|
          case mention['form']
            #when '-'
            #  $stderr.puts "Citationer did not handle: " + mention['matched'].to_s
              # this is a reference that Citationer did not know how to handle....
            when 'cfr'
              mention['cite'] = /\(/.match(mention['cite']).pre_match if mention['cite'] =~ /\(/
              thisuri = RDF::URI('http://liicornell.org/liicfr/' + mention['cite'].gsub(/\s+/,'_'))
              graph << [puri, clsauthor.refCFR,thisuri]
            when 'usc'
              mention['cite'] = /\(/.match(mention['cite']).pre_match if mention['cite'] =~ /\(/
              thisuri = RDF::URI('http://liicornell.org/liiuscode/' + mention['cite'].gsub(/\s+/,'_'))
              graph << [puri, clsauthor.refUSCode,thisuri]
            when 'statl'
              thisuri = RDF::URI('http://liicornell.org/liistat/' + mention['cite'].gsub(/\s+/,'_'))
              graph << [puri, clsauthor.refStatL,thisuri]
            when 'scotus'
              # chop off everything but volume and page reference
              chopped = /[0-9]+\s+US\s+[0-9]+/.match(mention['cite']).to_s
              thisuri = RDF::URI('http://liicornell.org/liiscotus/' + chopped.gsub(/\s+/,'_'))
              graph << [puri, clsauthor.refSCOTUS,thisuri]
              graph << [puri, clsauthor.citedPage, RDF::URI(mention['url'])]
            when 'topn'
              # look up dbPedia entry
              looker = DBPEDIA_LOOKUP_PREFIX + "#{CGI::escape(mention['cite'])}"
              c = Curl.get(looker) do |c|
                c.headers['Accept'] = 'application/json'
              end
              # unfortunately, the QueryClass parameter for dbPedia lookups is not much help, since class information
              # is often missing.  Best alternative is to use a filter based on dbPedia categories.  Crudely implemented
              # here as a string match against a series of keywords

              JSON.parse(c.body_str)['results'].each do |entry|
                use_me = false
                entry['categories'].each do |cat|
                  use_me = true if cat['label'] =~ /\b(law|legislation|government|Act)\b/
                end
                graph << [puri, clsauthor.refDBPedia,RDF::URI(entry['uri'])]  if use_me
              end
              thisuri = RDF::URI('http://liicornell.org/liitopn/' + mention['cite'].downcase.gsub(/\s+/,'_'))
              graph << [puri, clsauthor.refPopName,thisuri]
            else
              graph << [puri, clsauthor.citedPage,URI::encode(mention['url'])] unless mention['url'].nil?
          end
        end
      end
    end

  end

#-- override to_s, mostly for debugging purposes
  def to_s
    strang = <<-"eos"
Title: #{@title}
Online date: #{@online_date}
Publication date: #{@pub_date}
DOI: #{@doi}
PDF URL: #{@paper_url}

Abstract: #{@abstract}

Keywords: #{@keywords.join("\n")}
JEL classification: #{@jelcodes.join("\n")}
Coauthors (SSRN): #{@coauthors.join("\n")}
Abstract views: #{@abstract_views}
Downloads: #{@paper_dls}
Citations: #{@paper_citations}
Footnotes: #{@paper_footnotes}
Download rank: #{@dl_rank}
    eos
    return strang
  end
end

#-- class for modeling/constructing SSRN author pages

class SSRNAuthorPage
  attr_reader :ssrn_id, :abstractlist , :firstName , :lastName
  def initialize(my_ssrn_id, author_uri)
    @author_URI = author_uri
    @ssrn_id = my_ssrn_id
    @abstractlist = Array.new()
    @lastName = nil
    @firstName = nil
    begin
      html = Net::HTTP.get(URI(SSRN_AUTHOR_PREFIX+@ssrn_id))
      raise "Author listing page for ID #{@ssrn_id} unavailable" unless html
    rescue Exception => e
      puts e.message
      puts e.backtrace.inspect
      return nil
    end
    # SSRN throws javascript in at the top, just as it does on the Abstract pages, but this time there's not even a
    # DOCTYPE declaration. *sigh*
    html.sub!(/^.*<html/m,'<html')
    # also, too, bogus <nobr> tags
    html.gsub!(/<\/*nobr>/m, '')
   # clean_html = SimpleTidy.clean(html, :force_output => true)
    clean_html = Nokogiri::HTML(html).to_html
    @doc = Nokogiri::HTML(clean_html)
  end

  #-- gather the list of abstract ids for each author
  def scrape
    @doc.xpath("//a[@class='textlink']").each do |link|
      stuff = /http:\/\/ssrn\.com\/abstract=([0-9]+)/.match(link['href'])
      @abstractlist.push stuff[1] if stuff
    end
    # get author name information
    namestring = @doc.xpath("//h1")[0].inner_text
    @lastName,@firstName = namestring.split
    @lastName.gsub!(/,$/,'')
  end

  #-- process each of the abstracts listed on the page

  def process_abstracts
    @abstractlist.each do |absnum|
      abstract =  SSRNAbstractPage.new(absnum, @ssrn_id, @author_URI)
      abstract.scrape
      abstract.create_triples
    end
  end

  def process_paper_citations(browser, stashdir)
      @abstractlist.each do |absnum|
        abstract =  SSRNAbstractPage.new(absnum, @ssrn_id, @author_URI)
        abstract.extract_paper_citations(browser, stashdir)
      end
    end

  #-- override to_s for diagnostic purposes
  def to_s
    strang = <<-"eos"
     #{@abstractlist.join("\n")}
  eos
  end
end


class CLSAuthor
  # these variables don't follow ruby conventions --  they're named to correspond to properties in the data model
  # in a vain attempt to avoid confusion
  attr_accessor :birthYear,:deathYear,:firstName, :middleName, :lastName, :gPlusID, :gScholarID, :liiScholarID
  attr_accessor :openGraphID, :orcidID, :ssrnAuthorID, :worldCatID, :clsBio, :linkedInProfile, :homepage
  attr_accessor :viafID, :crossRefID, :bePressID, :dbPediaID , :freeBaseID
  def initialize(author_uri)
    @liiScholarID = author_uri
    @birthYear,@deathYear,@firstName,@middleName,@lastName,@gPlusID,@gScholarID = (0..6).map{nil}
    @openGraphID,@orcidID,@ssrnAuthorID,@worldCatID,@clsBio,@linkedInProfile,@homepage = (0..6).map{nil}
    @viafID,@crossRefID,@bePressID,@dbPediaID = (0..3).map{nil}
  end

  #-- create triples for everything we know about the author
  def create_triples(clsauthor, bibo)
    myuri = RDF::URI(@liiScholarID)
    myssrnuri = RDF::URI(LII_SSRN_AUTHOR_URI_PREFIX + @ssrnAuthorID)
    RDF::Writer.for(:ntriples).new($stdout) do |writer|
      writer << RDF::Graph.new do |graph|
        graph << [myuri, RDF.type, clsauthor.CLSAuthor]
        graph << [myssrnuri, RDF.type, clsauthor.SSRNAuthor ]
        graph << [myuri, OWL.sameAs, myssrnuri] unless @ssrnAuthorID.empty?

        graph << [myuri, clsauthor.birthYear, @birthYear] unless @birthYear.empty?
        graph << [myuri, clsauthor.deathYear, @deathYear] unless @deathYear.empty?
        graph << [myuri, FOAF.givenName, @firstName] unless @firstName.empty?
        graph << [myuri, clsauthor.middlename, @middleName] unless @middleName.empty?
        graph << [myuri, FOAF.familyName, @lastName] unless @lastName.empty?

       unless @gPlusID.empty?
         # fakeid = RDF::URI("http://liicornell.org/googleplus/" + @gPlusID)
         # graph << [fakeid, RDF.type, clsauthor.GooglePlusProfile]
         # graph << [myuri, clsauthor.hasGooglePlusProfile, fakeid]
          graph << [myuri, clsauthor.gPlusProfile,RDF::URI(GPLUS_URI_PREFIX+@gScholarID) ]
        end

        unless @gScholarID.empty?
         # fakeid = RDF::URI('http://liicornell.org/googlescholar/' + @gScholarID)
         # graph << [fakeid, RDF.type, clsauthor.GoogleScholarPage]
         # graph << [myuri, clsauthor.hasGoogleScholarPage, fakeid]
          graph << [myuri, clsauthor.gScholarPage, RDF::URI(GSCHOLAR_URI_PREFIX + @gScholarID)]
        end

        unless @openGraphID.empty?
         # graph << [RDF::URI(OPENGRAPH_URI_PREFIX + @openGraphID), RDF.type, clsauthor.openGraphID]
         # graph << [myuri, OWL.sameAs, RDF::URI(OPENGRAPH_URI_PREFIX + @openGraphID)]
        end

        graph << [myuri, clsauthor.orcID, @orcidID] unless @orcidID.empty?
        graph << [myuri, clsauthor.ssrnAuthorID, @ssrnAuthorID] unless @ssrnAuthorID.empty?

        unless @worldCatID.empty?
          #fakeid = RDF::URI('http://liicornell.org/worldcat/' + Digest::MD5.hexdigest(@worldCatID))
          #graph << [fakeid, RDF.type, clsauthor.WorldCatPage]
          #graph << [myuri, clsauthor.hasWorldCatPage, fakeid]
          graph << [myuri, clsauthor.worldCatPage, RDF::URI(@worldCatID)]
        end

        graph << [myuri, clsauthor.institutionBio, @clsBio] unless @clsBio.empty?

        unless @linkedInProfile.empty?
          #fakeid = RDF::URI('http://liicornell.org/linkedin/' + Digest::MD5.hexdigest(@linkedInProfile))
          #graph << [fakeid, RDF.type, clsauthor.LinkedInProfile]
          #graph << [myuri, clsauthor.hasLinkedInProfile, fakeid]
          graph << [myuri, clsauthor.linkedInProfile, RDF::URI(@linkedInProfile)]
        end


        graph << [myuri, FOAF.homepage, @homepage] unless @homepage.empty?

        unless @viafID.empty?
          #fakeid = RDF::URI('http://liicornell.org/viaf/' + Digest::MD5.hexdigest(@viafID))
          #graph << [fakeid, RDF.type, clsauthor.ViafPage]
          #graph << [myuri, clsauthor.hasViafPage, fakeid]
          graph << [myuri, clsauthor.viafPage, RDF::URI(@viafID)]
        end

        graph << [myuri, clsauthor.crossRefID, @crossRefID] unless @crossRefID.empty?

        unless @bePressID.empty?
          #fakeid = RDF::URI('http://liicornell.org/bepress/' + Digest::MD5.hexdigest(@bePressID))
          #graph << [fakeid, RDF.type, clsauthor.BePressPage]
          #graph << [myuri, clsauthor.hasBePressPage, fakeid]
          graph << [myuri, clsauthor.bePressPage, RDF::URI(@bePressID)]
        end

        graph << [myuri, OWL.sameAs, RDF::URI(@dbPediaID)] unless @dbPediaID.empty?
        #graph << [myuri, OWL.sameAs, RDF::URI(@freeBaseID)] unless @freeBaseID.empty?
      end
    end
  end
  #-- incomplete string output for testing
  def to_s
    strang =<<-"eos"
    Last:  #{lastName}
    First: #{firstName}
    Middle: #{middleName}
  eos
   return strang
  end
end

#-- processes the configuration spreadsheet
#-- assumes first row of spreadsheet is column labels
#-- mapping of column labels to data elements is in the "populate_author" method
class CLSAuthorSpreadsheet
  attr_reader :author_list

  #TODO: this badly needs exception-handling
  # opens the author-info spreadsheet using Google Drive
  def initialize
    session = GoogleDrive.login(GOOGLE_UID,GOOGLE_PWD)
    @ws = session.spreadsheet_by_key(GOOGLE_SPREADSHEET_KEY).worksheets[0]
    @author_list = Array.new
    @colnames = Array.new
    get_colnames
    populate_list
  end

  # populates the authorlist data structure from the spreadsheet
  # work in row-major order starting from row 2
  def populate_list
    uricol = @colnames.index("clsScholarID")+1
    for row in 2..@ws.num_rows()
      break if @ws[row,1] =~ /Note|Stop|(^\s+)/i  || @ws[row,1].empty?
      if (! @ws[row,uricol].empty?)
        author = CLSAuthor.new(@ws[row,uricol])
        populate_author(row,author)
        @author_list.push(author)
      end
    end
  end

  # populates a single author entry
  # TODO -- find out what this does with null/empty values
  def populate_author(row, author)
    author.birthYear= @ws[row,@colnames.index("BirthYear")+1].strip
    author.deathYear = @ws[row,@colnames.index("DeathYear")+1].strip
    author.firstName=  @ws[row,@colnames.index("First name")+1].strip
    author.lastName= @ws[row,@colnames.index("Last name")+1].strip
    author.middleName= @ws[row,@colnames.index("Middle name")+1].strip
    author.gPlusID= @ws[row,@colnames.index("googlePlusID")+1].strip
    author.gScholarID= @ws[row,@colnames.index("googleScholarID")+1].strip
    author.liiScholarID= @ws[row,@colnames.index("clsScholarID")+1].strip
    author.openGraphID= @ws[row,@colnames.index("openGraphID")+1].strip
    author.orcidID=@ws[row,@colnames.index("orcID")+1].strip
    author.ssrnAuthorID= @ws[row,@colnames.index("ssrnID")+1].strip
    author.worldCatID= @ws[row,@colnames.index("worldCatID")+1].strip
    author.clsBio= @ws[row,@colnames.index("institutionBioURL")+1].strip
    author.linkedInProfile= @ws[row,@colnames.index("linkedInProfile")+1].strip
    author.homepage= @ws[row,@colnames.index("Homepage")+1].strip
    author.viafID= @ws[row,@colnames.index("viafID")+1].strip
    author.crossRefID= @ws[row,@colnames.index("crossRefID")+1].strip
    author.bePressID = @ws[row,@colnames.index("bePressID")+1].strip
    author.dbPediaID = @ws[row,@colnames.index("dbPediaID")+1].strip
    author.freeBaseID = @ws[row,@colnames.index("FreeBaseID")+1].strip
  end

  def process_papers
    @author_list.each do |author|
      next if author.ssrnAuthorID.empty?
      page = SSRNAuthorPage.new(author.ssrnAuthorID,author.liiScholarID)
      next if page.nil?
      page.scrape
      page.process_abstracts
    end
  end

  def process_extract_citations(browser,stashdir)
    @author_list.each do |author|
      next if author.ssrnAuthorID.empty?
      page = SSRNAuthorPage.new(author.ssrnAuthorID,author.liiScholarID)
      page.scrape
      page.process_paper_citations(browser,stashdir)
    end
  end

  # populates list of column names
  def get_colnames
    for col in 1..@ws.num_cols()
      @colnames.push(@ws[1,col])
    end
  end

  #-- create triples calls create_triples for each author in the list
  def create_triples
    clsauthor = RDF::Vocabulary.new(CLS_VOCABULARY)
    bibo = RDF::Vocabulary.new(BIBO_VOCABULARY)
    @author_list.each do |author|
      author.create_triples(clsauthor,bibo)
    end
  end

  # override puts for diagnostic purposes
  def to_s
    stuff = ""
    @author_list.each do |author|
      stuff = stuff + author.to_s
    end
    puts "#{stuff}"
  end
end


# show-running class
# TODO: set up for command line options
# output of everything currently goes to stdout

class CLSAuthorRunner
  def initialize (opt_hash)
    @opts =opt_hash
    @sheet = CLSAuthorSpreadsheet.new()
    @browser = nil # browser simulator
    @stashdir = nil # place to put downloaded pdfs, temporarily
  end

  def run
    # set up a browser simulator if it's needed
    if @opts.cited || @opts.test_abstract
      # make a one-time temporary directory
      @stashdir = Dir.mktmpdir
      # set up a browser simulator
      profile = Selenium::WebDriver::Firefox::Profile.new
      profile['browser.download.folderList'] = 2 #specifies custom location
      profile['browser.download.dir'] = "#{@stashdir}"
      profile['browser.helperApps.neverAsk.saveToDisk'] = "application/pdf,application/x-pdf,application/octet-stream"
      headless = Headless.new
      headless.start
      @browser = Watir::Browser.new :firefox, :profile => profile
      # go through signin procedure
      @browser.goto SSRN_LOGIN_AJAX
    end

    # do stuff
    run_authors if @opts.authors
    run_papers if @opts.abstracts
    run_authors_papers_with_citations if @opts.cited
    test_abstract_page if @opts.test_abstract
    test_paperlist if @opts.test_author
    test_spreadsheet if @opts.test_spreadsheet
    demo_citations if @opts.demo_citations

    # clean up
    if @opts.cited || @opts.test_abstract
      # kill off the browser simulator
      b.close
      headless.destroy
      Dir.unlink("#{stashdir}")
    end
  end
  def test_abstract_page
    pg = SSRNAbstractPage.new('2218855','489995')
    pg.scrape
    pg.create_triples
    pg.extract_paper_citations(@browser,@stashdir)
    puts "#{pg}"
  end
  def test_paperlist
    pg = SSRNAuthorPage.new('45120')
    pg.scrape
    puts "#{pg}"
  end
  def test_spreadsheet
    sheet = CLSAuthorSpreadsheet.new()
    sheet.create_triples
    stuff = sheet.to_s
    puts "#{stuff}"
  end
  def run_authors
    @sheet.create_triples
  end
  def run_papers
    @sheet.process_papers
  end
  def run_authors_papers_with_citations
     @sheet.process_extract_citations(@browser,@stashdir)
  end
  # limited set of authors for demo
  def demo_citations

  end
end

opts = Trollop::options do
  banner <<-EOBANNER
clsauthor generates triples for legal scholarship. See program header for explanations.
Output is sent to stdout, and can be redirected into a file.

Usage:
    clsauthor.rb [options]
where options are:
EOBANNER
  opt :authors, "Generate triples for authors"
  opt :abstracts, "Generate triples for paper metadata"
  opt :cited, "Generate triples for primary law cited in papers"
  opt :test_abstract, "Run scrape test for a single abstract"
  opt :test_author, "Run scrape test for a single author's papers"
  opt :test_spreadsheet, "Run spreadsheet dump"
  opt :demo_citations, "Run primary materials citations for a small precoded set of authors"
end
control = CLSAuthorRunner.new(opts)
control.run