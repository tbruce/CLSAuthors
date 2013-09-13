
#-- This code makes some assumptions.
# -- SSRN URLs follow the templates described by the constants defined below
# -- There is no paging of the list of papers displayed by an author page -- that is, all of an author's papers are
#    listed on a single page, no matter how many there are.


CLS_TRIPLE_FILE=''

# SSRN-related config information
SSRN_AUTHOR_PREFIX='http://papers.ssrn.com/sol3/cf_dev/AbsByAuth.cfm?per_id='
SSRN_ABSTRACT_PREFIX='http://papers.ssrn.com/sol3/papers.cfm?abstract_id='
LII_SSRN_URI_PREFIX='http://liicornell.org/ssrn/papers/'

# google related config information
GOOGLE_UID='access.lii.cornell@gmail.com'
GOOGLE_PWD='crankmaster'
GOOGLE_SPREADSHEET_KEY='0AkDG2tEbluFPdFhIT09tdnpKWHV2dHRNQUVMLXBNSHc'

CITATIONER_URI='http://mojo.law.cornell.edu/services/citationer/'

require 'rubygems'
require 'net/http'
require 'simple-tidy'
require 'nokogiri'
require 'chronic'
require 'google_drive'
require 'tempfile'
require 'curb'

#-- class for representing/modeling SSRN abstract pages

class SSRNAbstractPage
  attr_reader :paper_id,:author_id,:url,:keywords,:jelcodes,:coauthors,:abstract,:online_date,:pub_date,:doi,:title,:paper_url

  def initialize(my_id, my_ssrn_author_id)
    @paper_id = my_id
    @author_id = my_ssrn_author_id
    @url = SSRN_ABSTRACT_PREFIX + my_id
    @paper_URI = LII_SSRN_URI_PREFIX + my_id

    @keywords = Array.new()
    @jelcodes = Array.new()
    @coauthors = Array.new()
    @abstract = nil
    @online_date = nil
    @pub_date = nil
    @doi = nil
    @title = nil
    @paper_url = nil
    @abstract_views = nil
    @paper_dls = nil
    @paper_citations = nil
    @paper_footnotes = nil
    @dl_rank = nil
    @extracted_citations = Array.new()

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
    @doc = Nokogiri::HTML(clean_html)
  end

  #-- scrape the contents of the page
  def scrape
    scrape_metas
    scrape_stats
    scrape_authors
    scrape_abstract
    scrape_jelcodes
    extract_paper_citations
  end

  #-- get interesting metatag content
  def scrape_metas
      @title = @doc.at_xpath("//meta[@name='citation_title']")["content"]
      @online_date = @doc.at_xpath("//meta[@name='citation_online_date']")["content"]
      @pub_date = @doc.at_xpath("//meta[@name='citation_publication_date']")["content"]
      @doi = @doc.at_xpath("//meta[@name='citation_doi']")["content"]
      @paper_url =@doc.at_xpath("//meta[@name='citation_pdf_url']")["content"]
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
      num = stat.inner_text().gsub!(/[^0-9]/,'').to_i
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
       @coauthors.push(auth_id) unless auth_id == @author_id
    end
  end

  def scrape_abstract
      @abstract = @doc.at_xpath("//div/div/div/font").inner_text()
  end

  def scrape_jelcodes
    @doc.xpath("//div/div/div/p/font").each do |chunk|
      stuff = /JEL\s*Classification:\s*((([A-Z][0-9]+),*\s*)+)/.match(chunk.inner_text())
      if stuff
        @jelcodes = stuff[1].split(/,\s*/)
      end
    end
  end

  def extract_paper_citations
    fullpaper = SSRNPaper.new(@paper_url)
    @extracted_citations = fullpaper.extract_citations
  end

  def create_triples
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
  end
end

class SSRNPaper
  def initialize(paper_url)
    # could be HTML, PDF, pretty much anything
    @stuff = Net::HTTP.get(URI(paper_url))
    @citation_list = Array.new
  end

  #-- pull out citations using LII Citationer service
  def extract_citations
    postfile = Tempfile.new('clsauthor')
    postfile.write(@stuff)
    postfile.close

    c = Curl::Easy.new(CITATIONER_URI)
    c.multipart_form_post = true
    c.http_post(Curl::PostField.file('files', postfile.path))
    jsn = c.body_str
    puts "#{jsn}"
    return @citation_list
  end
  def create_triples

  end
end

#-- class for modeling/constructing SSRN author pages

class SSRNAuthorPage
  attr_reader :ssrn_id, :abstractlist
  def initialize(my_ssrn_id, author_uri)
    @author_URI = author_uri
    @ssrn_id = my_ssrn_id
    @abstractlist = Array.new()
    begin
      html = Net::HTTP.get(URI(SSRN_AUTHOR_PREFIX+@ssrn_id))
      raise "Author listing page for ID #{@ssrn_id} unavailable" unless html
    rescue Exception => e
      puts e.message
      puts e.backtrace.inspect
    end
    # SSRN throws javascript in at the top, just as it does on the Abstract pages, but this time there's not even a
    # DOCTYPE declaration. *sigh*
    html.sub!(/^.*<html/m,'<html')
    # also, too, bogus <nobr> tags
    html.gsub!(/<\/*nobr>/m, '')
    clean_html = SimpleTidy.clean(html, :force_output => true)
    @doc = Nokogiri::HTML(clean_html)
  end

  #-- gather the list of abstract ids for each author
  def scrape
    @doc.xpath("//a[@class='textlink']").each do |link|
      stuff = /http:\/\/ssrn\.com\/abstract=([0-9]+)/.match(link['href'])
      @abstractlist.push stuff[1] if stuff
    end
  end

  #-- process each of the abstracts listed on the page

  def process_abstracts
    @abstractlist.each do |absnum|
      abstract =  SSRNAbstractPage.new(absnum, @ssrn_id)
      abstract.scrape
      abstract.create_triples
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
  # these variables don't follow ruby conventions -- they're named to correspond to properties in the data model
  # in a vain attempt to avoid confusion
  attr_accessor :birthday,:dateOfDeath,:firstName, :middleName, :lastName, :gPlusID, :gScholarID, :liiScholarID
  attr_accessor :openGraphID, :orcidID, :ssrnAuthorID, :worldCatID, :clsBio, :linkedInProfile, :homepage
  attr_accessor :viafID, :crossRefID
  def initialize(author_uri)
    @liiScholarID = author_uri
  end

  #-- create triples for everything we know about the author
  def create_triples


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

  # this badly needs exception-handling
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
      author = CLSAuthor.new(@ws[row,uricol])
      populate_author(row,author)
      @author_list.push(author)
    end
  end

  # populates a single author entry
  def populate_author(row, author)
    author.birthday= @ws[row,@colnames.index("Birthdate")+1]
    author.dateOfDeath= @ws[row,@colnames.index("DeathDate")+1]
    author.firstName=  @ws[row,@colnames.index("First name")+1]
    author.lastName= @ws[row,@colnames.index("Last name")+1]
    author.middleName= @ws[row,@colnames.index("Middle name")+1]
    author.gPlusID= @ws[row,@colnames.index("googlePlusID")+1]
    author.gScholarID= @ws[row,@colnames.index("googleScholarID")+1]
    author.liiScholarID= @ws[row,@colnames.index("clsScholarID")+1]
    author.openGraphID= @ws[row,@colnames.index("openGraphID")+1]
    author.orcidID=@ws[row,@colnames.index("orcID")+1]
    author.ssrnAuthorID= @ws[row,@colnames.index("ssrnID")+1]
    author.worldCatID= @ws[row,@colnames.index("worldCatID")+1]
    author.clsBio= @ws[row,@colnames.index("clsBioURL")+1]
    author.linkedInProfile= @ws[row,@colnames.index("linkedInProfile")+1]
    author.homepage= @ws[row,@colnames.index("Homepage")+1]
    author.viafID= @ws[row,@colnames.index("viafID")+1]
    author.crossRefID= @ws[row,@colnames.index("crossRefID")+1]
  end

  def process_papers
    @author_list.each do |author|
      next if author.ssrnAuthorID.empty?
      page = SSRNAuthorPage.new(author.ssrnAuthorID,author.liiScholarID)
      page.process_abstracts
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
    @author_list.each do |author|
      author.create_triples
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


# pseudocode
# check to see if we're printing out triples or updating the endpoint
# get a list of author objects from the spreadsheet
# emit the author triples however
# for each author, get the papers
# emit the paper triples however

# page/paperlist test
#pg = SSRNAuthorPage.new('45120')
#pg.scrape
#puts "#{pg}"

# abstract page test
pg = SSRNAbstractPage.new('2218855','489995')
pg.scrape
puts "#{pg}"

# spreadsheet test
#sheet = CLSAuthorSpreadsheet.new()
#stuff = sheet.to_s
#puts "#{stuff}"