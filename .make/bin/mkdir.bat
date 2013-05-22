@echo off
ruby -e 'require "fileutils"; ARGV.shift; FileUtils.mkdir_p(ARGV)' -- %*
