#!/usr/bin/env ruby
# This is an alternative to the check_log plugin that ships with nagios.
# Unlike check_log, this plugin tracks where in the logfile
# it should continue from, not by copying the whole log,
# but by recording the first line of the log (to ensure
# the file has not changed) and its last byte position inside the logfile.
#
# Copyright (C) 2013  Frode Egeland <egeland[at]gmail.com>
# https://github.com/egeland/nagios-check_logpattern
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

working_dir = '/tmp' # This is where the seek file lives

#########################################
# Do not edit anything below this point #
# (Unless you know what you are doing)  #
#########################################

#####################
# Class definitions #
#####################
class Lastpos
  def initialize(seekfile)
    @seekfile = seekfile
    @line_to_match = ''
    @prev_read_line = 0
    if File.exists?(@seekfile) then
      fhr = File.open(@seekfile,'r') # 'read' file handle is opened if the file exists
      @line_to_match = fhr.gets
      @prev_read_line = fhr.gets
      fhr.close
    end
  end
  def get_line()
    return @line_to_match
  end
  def get_pos()
    return @prev_read_line
  end
  def set_line(line)
    @line_to_match = line
  end
  def set_pos(pos)
    @prev_read_line = pos.to_i
  end
  def save()
    begin
      File.open(@seekfile,'w') do |wfh| # 'write' file handle
        wfh.puts(@line_to_match)
        wfh.puts(@prev_read_line)
      end
    rescue
      puts "Trouble: Unable to save to #{@seekfile}"
    end
  end
end # of class Lastpos

class Logfile
  def initialize(logfile)
    @logfile = logfile
    begin
      @fh = File.open(@logfile,'r')
    rescue
      puts "CRITICAL: File not found: #{@logfile}"
      exit 2
    end
    @fh.pos = 0 # make sure we're reading the first line
    @firstline = @fh.gets()
  end
  def get_line()
    return @firstline
  end
  def set_pos(line)
    # TODO: Handle exceptions if line > num of lines in file
    @fh.pos = line.to_i
  end
  def match_count(pattern)
    counter = 0
    @fh.each_line() do |line|
      if line.include? pattern
        counter = counter + 1
      end
    end
    return counter
  end
  def get_pos()
    return @fh.pos
  end
  def close()
    @fh.close()
  end
end # of class Logfile

###################
# Options Parsing #
###################
require 'optparse'
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{$0.split('/')[-1]} [OPTIONS]"
  opts.on("-l","--logfile LOGFILE",String,"Supply the LOGFILE to monitor") do |logfile|
    options[:logfile] = logfile
  end
  opts.on( "-t", "--text-to-match PATTERN",String,"Enter a text PATTERN to search for") do |textpattern|
    options[:textpattern] = textpattern
  end
  opts.on( "-w", "--warn-level WARNLEVEL", Integer,
           "Warn on WARNLEVEL number of matches") do |wl|
    options[:warnlevel] = wl
  end
  opts.on( "-c", "--crit-level CRITLEVEL", Integer,
           "Crit on CRITLEVEL") do |cl|
    options[:critlevel] = cl
  end
  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

if options.length != 4
  puts "UNKNOWN: Incorrect number of arguments (#{options.length}), should be 4. Run with -h for help."
  exit 3
end

######################
# Main program logic #
######################

# Prepare our objects
logfile = Logfile.new(options[:logfile])
seekfile = "#{working_dir}/#{options[:logfile].split('/')[-1].split('.')[0]}_log.seek"
lastpos = Lastpos.new(seekfile)

# If we are in the same file as last time
if logfile.get_line() == lastpos.get_line() then
  logfile.set_pos(lastpos.get_pos())
end

# Test the supplied pattern
matches = logfile.match_count(options[:textpattern])

# Save our place for next time and tidy up
lastpos.set_pos(logfile.get_pos())
lastpos.set_line(logfile.get_line())
lastpos.save()
logfile.close()

# Supply output in nagios format
if matches >= options[:critlevel]
  puts "CRITICAL: #{matches} lines matching"
  exit 2
elsif matches >= options[:warnlevel]
  puts "WARNING: #{matches} lines matching"
  exit 1
else
  puts "OK: No matches found"
  exit 0
end
