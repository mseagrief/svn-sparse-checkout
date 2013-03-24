#!/usr/bin/ruby
# Copyright (C) 2011 Mark Seagrief
#
# checkout.rb is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License,
# or (at your option) any later version.
#
# checkout.rb is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with checkout.rb. If not, see http://www.gnu.org/licenses/.
#
$defaultMap = "code"
$configFolder = "sparse"

require "fileutils"
require "yaml"

############################################################################
def getTemp
	if @platform=="windows"
		return 'c:\windows\temp'
	end

	return "/tmp"
end

############################################################################
def usage
	puts "#{$0} [--map|-m name] [--listmaps] [--revision|-r rev] svn://server/path [checkoutfolder]"
	puts ""
	puts "This script produces a sparse checkout."
	puts ""
	puts "Optional extra file sets can be brought in with the --map option."
	puts ""
	puts "--map name           Include the named checkout map in the checkout."
	puts "                      use --listmaps for a complete list"
	puts "--listmaps           List all of the current checkout maps"
	puts ""
	puts "-rrev                Do the sparse checkout of a particular revision"
	puts ""
	puts "svn://server/path    The svn url to checkout from e.g. "
	puts "                      svn://server/trunk"
	puts ""
	puts "checkoutfolder       Optional folder name to checkout into instead of build"
	puts ""
	puts "The platform will be autodetected."
	puts ""
	puts ""

	exit 1
end

############################################################################
def readFile(fileName)
	begin
		ret = ''
		file = File.new(fileName, 'r')
		while(line = file.gets)
			ret += line
		end
		file.close

		ret
	rescue
		puts "Unable to read "+fileName+", "+$!
		exit 1
	end
end

############################################################################
def listMaps(url)
	puts ""
	puts "Currently defined checkout maps"
	puts ""
	tmp = getTemp
	fileName = "#{tmp}/list.txt"
	system("svn ls #{url}/#{$configFolder} > #{fileName}")
	if File.exists?( fileName )
		File.open( fileName ).each_line {|line|

			line = line.strip()
			confFile = "#{tmp}/#{line}"

			system("svn cat -r#{@rev} #{url}/#{$configFolder}/#{line} > #{confFile}")
			str = readFile( confFile )
			FileUtils.rm( confFile )

			name = line.gsub(/\.yaml$/,"")
			if str =~ /^description: (.+)/ then
				puts "%-20s%s" % [name,$1]
			end
		}
	end

	exit 1
end

############################################################################
def parseSingleConfig(url,yamlFile)
	includemap = []

	yamlObj = YAML::parse(yamlFile)
	obj = yamlObj.transform

	#process any includes
	includes = []
	if obj['include'].kind_of? String then
		includes.push( obj['include'] )
	elsif obj['include'].kind_of? Array then
		includes = obj['include']
	end

	#process any includes
	includes.each { |inc|
		doDelete = false
		confFile = inc

		if !File.exists?(confFile) then
			confFile = getTemp+"/"+inc
			system("svn cat -r#{@rev} #{url}/#{$configFolder}/#{inc} > #{confFile}")
			doDelete = true
		end

		if !File.exists?(confFile) then
			puts "Unable to find #{confFile} on disk or in svn"
			exit 1
		end

		puts "Reading: #{confFile}"
		file = File.open( confFile )
		map = parseSingleConfig( url, file )
		file.close()

		if doDelete then
			FileUtils.rm(confFile)
		end

		includemap.concat( map )
	}

	if obj['files'].kind_of? Hash then
		if obj['files']['all'].kind_of? Array then
			obj['files']['all'].each { |f| includemap.push f }
		end
		if obj['files']['linux'].kind_of? Array and @platform=="linux" then
			obj['files']['linux'].each { |f| includemap.push f }
		end
		if obj['files']['windows'].kind_of? Array and @platform=="windows" then
			obj['files']['windows'].each { |f| includemap.push f }
		end
	else
		puts "Badly formed config file, files section not a Hash"
	end

	return includemap
end

############################################################################
def parseConfig(url,yamlFile)
	yamlObj = YAML::parse(yamlFile)
	obj = yamlObj.transform

	#base to strip from paths and add to url?
	baseStrip = ""
	puts obj['base']
	if obj['base'] != nil then
		baseStrip = obj['base']
		@urlExtra = obj['base']
	end

	#process this file
	yamlFile.seek(0,IO::SEEK_SET)
	map = parseSingleConfig( url, yamlFile )
	@checkoutmap.concat( map )

	#strip off the base part from the file maps
	checkouttemp = []
	@checkoutmap.each { |inc|
		checkouttemp.push( inc.gsub(/^#{baseStrip}/,"") )
	}

	@checkoutmap = checkouttemp
end

############################################################################
def runSvnCmd(cmd)
	puts cmd
	if !system(cmd) then
		puts "#{cmd} failed, aborting"
		exit 1
	end
end

############################################################################
#some global variables
@checkoutmap = []
@platform = 'linux'
@urlExtra = ''
@rev = 'HEAD'

#what platform?
if RUBY_PLATFORM =~ /-linux/i
	puts "Platform: Linux"
	@platform = "linux"
end
if RUBY_PLATFORM =~ /-mswin32/i
	puts "Platform: Windows"
	@platform = "windows"
end

mapNames = []
doListMaps = false
svnArgs = []

#lets process some command line args
argc = 0
i = 0
while i<ARGV.length-1
	if ARGV[i] == "--map"then
		mapNames.push( ARGV[i+1] )
		i = i+1
	elsif ARGV[i] =~ /^-m(.+)/ then
		mapNames.push( $1 )
	elsif ARGV[i] == "-r" || ARGV[i] == "--revision" then
		@rev = ARGV[i+1]
		i = i+1
	elsif ARGV[i] =~ /^-r(.+)/ then
		@rev = $1
	elsif ARGV[i] == "--listmaps" then
		doListMaps = true
	elsif ARGV[i] =~ /^(--.+)$/ then
		svnArgs.push( $1 )
	else
		break
	end

	i = i+1
	argc = i
end

#no maps specified, default to tog
if mapNames.length==0 then
	mapNames.push( $defaultMap )
end

#give them some help
if (ARGV.length-argc)<1 then
	usage
end

#grab the checkout url
url = ARGV[argc]
url = url.gsub(/\/$/,"")

if !(url =~ /^(.+):\/\//) then
	puts "Unrecognised svn url: #{url}"
	usage
end

#user asked us to list the available checkout definitions
if doListMaps then
	listMaps(url)
end

#parse the chosen configs
mapNames.each { |conf|
	if conf =~ /\.yaml$/ then
		#user supplied a file
		puts "Reading checkout map from: #{conf}"
		parseConfig( url, File.open( conf ) )
	else
		#need to get from svn
		puts "Reading checkout map from: #{url}/#{$configFolder}/#{conf}.yaml@#{@rev}"
		tmp = getTemp

		cmd = "svn -r#{@rev} cat #{url}/#{$configFolder}/#{conf}.yaml > #{tmp}/#{conf}.yaml"
		runSvnCmd(cmd)

		file = File.open( "#{tmp}/#{conf}.yaml" )
		parseConfig( url, file)
		file.close
		FileUtils.rm("#{tmp}/#{conf}.yaml")
	end
}

puts ""
puts "Checkout url: #{url}"
url = url+"/"+@urlExtra
url = url.gsub(/\/$/,"")
puts "Checkout url with base from config: #{url}"

checkoutfolder = ""
#is there a checkout folder name?
if ARGV.length-argc>1 then
	checkoutfolder = ARGV[argc+1]
end

#tell people what is going on
puts ""
if checkoutfolder=="" then
	puts "Checking out from: #{url}"
else
	puts "Checking out from: #{url} into #{checkoutfolder}"
end

#order the checkouts so we work down the tree and do file checkouts first
@checkoutmap.sort! { |a,b| a.count("/") <=> b.count("/") }
@checkoutmap.sort! { |a,b| b.count("@") <=> a.count("@") }
@checkoutmap.each { |line|
	puts line
}

#exit 0

#extra svn commands
svnExtraParams = ""
svnArgs.each { |arg| svnExtraParams = svnExtraParams + " " + arg }
svnExtraParams = svnExtraParams.strip()

puts "SVN extra parameters: #{svnExtraParams}"

#do the top level checkout
cmd = "svn #{svnExtraParams} -r#{@rev} checkout --depth empty #{url} #{checkoutfolder}"
runSvnCmd(cmd)

#go into the folder
if checkoutfolder=="" then
	FileUtils.chdir( url.split("/").last )
else
	FileUtils.chdir( checkoutfolder )
end

#do the checkouts!
@checkoutmap.each { |line|
	path = line.gsub(/(@|\*)$/,'')

	base = "."

	#make sure the path to the folder/files we want is already checkedout
	path.split("/").each { |part|
		base = File.join(base,part)

		#does the folder exist already?
		if !File.exists?(base) then
			cmd = "svn #{svnExtraParams} -r#{@rev} update --set-depth empty #{base}"
			runSvnCmd(cmd)
		end
	}

	path = File.join(".",path)

	if line.match(/@/) then
		cmd = "svn #{svnExtraParams} -r#{@rev} update --set-depth files #{path}"
		runSvnCmd(cmd)
	elsif line.match(/\*/) then
		cmd = "svn #{svnExtraParams} -r#{@rev} update --set-depth infinity #{path}"
		runSvnCmd(cmd)
	end
}
