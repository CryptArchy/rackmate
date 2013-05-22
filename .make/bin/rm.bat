@echo off
ruby -e 'require "fileutils"; ARGV.shift; FileUtils.rm_rf(ARGV)' --  %*
