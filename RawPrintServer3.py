#!/usr/bin/python

"""
RawPrintServer.py -- Raw Print Server Main Module
"""

###########################################################################
# RawPrintServer.py -- Raw Print Server Main Module
# Copyright 2005 Chris Gonnerman
#  ** ported to Python 3, removed the config file setup utility,  **
#  ** and consolidated all codes to single file - KL Lai 2021     **
#  ** on Windows platform, printer_name is now taking the printer **
#  ** port name, network share name, or a target folder instead   **
#  ** of the printer name as normally shown in the printer list   **
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without 
# modification, are permitted provided that the following conditions
# are met:
# 
# Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer. 
# 
# Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution. 
# 
# Neither the name of the author nor the names of any contributors
# may be used to endorse or promote products derived from this software
# without specific prior written permission. 
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
###########################################################################

## rpsconf.py -- Raw Print Server Config File Handler ##

class rpsconf:

    import sys, os

    try:
        # look for the user's preferred configuration file
        configfile = os.environ["RPSCONF"]
    except KeyError:
        # don't have it, so let's think up a reasonable default
        if sys.platform == "win32":
            #configfile = r"C:\Windows\System32\rpsrv.conf"
            configfile = r".\rpsrv.conf"
        else:
            configfile = "/etc/rpsrv.conf"
    #

    cfgskel = {
        "spooldir": None,
        "logfile": None,
        "printer": [ ],
    }

    @staticmethod
    def createconfig():
        """
        createconfig(): create an empty configuration 
                        dictionary based on the skeleton.
        """
        cfg = { }
        # dang this is ugly.  need to use a more generic object copier.
        # need to read the manual.
        for k in rpsconf.cfgskel.keys():
            if rpsconf.cfgskel[k] is None:
                cfg[k] = None
            else:
                cfg[k] = [ ]
            #
        #
        return cfg
    #

    @staticmethod
    def loadconfig(fn = None):
        """
        loadconfig(fn):  load configuration from the named file.  if the
                         name isn't given, load the config from the default
                         location.  returns a dictionary containing the
                         configuration settings.  errors are printed to
                         stdout but the configuration is created anyway.
        """
        print("loadconfig() ...")
        cfg = rpsconf.createconfig()
        if fn is None: fn = rpsconf.configfile
        print(fn)
        try:
            fp = open(fn, "r")
        except:
            return cfg
        #
        lines = fp.readlines()
        fp.close()
        ##print(lines)
        for i in range(len(lines)):
            l = lines[i].strip()
            if l and l[0] != '#':
                try:
                    cmd, arg = l.split("=", maxsplit = 1)
                except:
                    print("Parse Error in <%s> at line %s" % (fn, i))
                    continue
                cmd = cmd.strip()
                arg = arg.strip()
                if cmd not in cfg:
                    print("Illegal Command <%s> in <%s> at line %d" % (cmd, fn, i))
                    continue
                if type(cfg[cmd]) is type([]):
                    cfg[cmd].append(arg)
                elif cfg[cmd] is not None:
                    print("Duplicate Command <%s> in <%s> at line %d" % (cmd, fn, i))
                    continue
                else:
                    cfg[cmd] = arg
        #
        return cfg
    #
#

###########################################################################

## spooler.py -- Raw Print Server Spooler Access Module

class spooler:
    import sys

    class base_printer:
        def __init__(self, printer_name = None):
            self.printer_name = printer_name

    if sys.platform == "win32":
        class printer(base_printer):
            def sendjob2(self, jobname):
                import shutil;  shutil.copyfile(jobname, self.printer_name)
            #
        #
    else:
        import os
        class printer(base_printer):
            def sendjob2(self, jobname):
                fp = open(jobname, "rb")
                out = os.popen("lpr -P'%s' >/dev/null 2>&1" % self.printer_name, "wb")
                blk = fp.read(8192)
                while blk:
                    out.write(blk)
                    blk = fp.read(8192)
                #
                rc = out.close()
                if rc is not None: print("Error: lpr returns %02x" % rc)
                fp.close()
            #
        #
#

###########################################################################

## logger.py -- Raw Print Server Logging Module

class logger:
    __version__ = "1.1"

    import sys, time

    def logtime():
        import time
        return time.strftime("[%Y/%m/%d %H:%M:%S]", \
            time.localtime(time.time()))
    #
    class LogFile:
        def __init__(self,file):
            self.file = file
            self.remaining = ""
        #
        def write(self, s):
            if type(s) is type(""):
                if s:
                    cont = ""
                    l = (self.remaining + s).split("\n")
                    self.remaining = ""
                    # if there are more than one item in the list,
                    # and the last item is not "", the last part
                    # did not end "\n" and will go into remaining.
                    if len(l) > 1:
                        if l[-1] != "": self.remaining = l[-1]
                        del l[-1]
                    elif len(l) == 1:
                        self.remaining = l[0]
                        l = []
                    #
                    for i in l:
                        if i:
                            self.file.write(logger.logtime() + " " + cont + i + "\n")
                        else:
                            self.file.write("\n")
                        cont = ": "
                    #
                self.file.flush()
            else:
                raise TypeError("invalid data for write() method")
            #
        #
        def close(self):
            return self.file.close()
        #

#

###########################################################################

## printserver.py -- Raw Print Server Core Module ##

class printserver:

    import socket, asyncore, os, sys

    ###########################################################################
    # Variable Initialization
    ###########################################################################

    # jobnumber is global because multiple server contexts may share it
    jobnumber = 0
    JOBNAME = "RawPrintJob%05d.prn"
    servers = []

    ###########################################################################
    # Class Definitions
    ###########################################################################

    class print_server(asyncore.dispatcher):
        def __init__(self, addr, port, printer):
            self.addr = addr
            self.port = port
            self.printer = printer
            print("Starting Printer <%s> on port %d" \
                % (self.printer.printer_name, self.port)
            )
            asyncore.dispatcher.__init__(self)
            self.create_socket() ## socket.AF_INET, socket.SOCK_STREAM
            self.bind((addr, port))
            self.listen(5)
        #
        def writable(self):
            return 0
        #
        def readable(self):
            return self.accepting
        #
        def handle_read(self):
            pass
        #
        def handle_connect(self):
            pass
        #
        def handle_accept(self):
            #global jobnumber
            try:
                conn, addr = self.accept()
            except:
                print("Error, Accept Failed!")
                return
            #
            printserver.jobnumber += 1
            handler = printserver.print_handler(
              conn, addr, self, printserver.jobnumber
            )
        #
        def handle_close(self):
            print("Stopping Printer <%s> on port %d" \
                % (self.printer.printer_name, self.port)
            )
            self.close()
        #
    #  class print_server()

    class print_handler(asyncore.dispatcher):

        jobname = None
        fp = None

        def __init__(self, conn, addr, server, jobnumber):
            asyncore.dispatcher.__init__(self, sock = conn)
            self.addr = addr
            self.server = server
            self.jobname = printserver.JOBNAME % jobnumber
            self.fp = open(self.jobname, "wb")
            print("Receiving Job from %s for Printer <%s> (Spool File %s)" \
                % (addr, self.server.printer.printer_name, self.jobname)
            )
        #
        def handle_read(self):
            data = self.recv(8192)
            if self.fp: self.fp.write(data)
        #
        def writable(self):
            return 0
        #
        def handle_write(self):
            pass
        #
        def handle_close(self):
            print("Printer <%s>: Printing Job %s" \
                % (self.server.printer.printer_name, self.jobname)
            )
            if self.fp:
                self.fp.close()
                self.fp = None
            #
            self.server.printer.sendjob2(self.jobname)

            ## below will delete/keep the print job spool file
            if False :
              try:
                os.remove(self.jobname)
              except:
                print("Can't Remove <%s>" % self.jobname)
              #
            #
            self.close() ## must close, else will keep processing this
        #
    # class print_handler(asyncore.dispatcher)

    def setuplog(logfn):
        if not logfn: logfn = "rps.log"
        print("... " + logfn)
        log = logger.LogFile(open(logfn, "a"))
        log.write("log start ...\n")
        sys.stderr = sys.stdout = log
    #

    def chdir(spooldir):
        if spooldir:
            os.chdir(spooldir)
            # don't do that twice!
            spooldir = None
        else:
            # config is missing; need a safe place to call "home"
            os.chdir("/tmp")
        #
        os.umask(0o22) ## allows me to write data, but anyone can read data
    #

    def mainloop(config):
        if len(config["printer"]) == 0 :
            print("invalid config!")
            return
        #
        if config["spooldir"]: os.chdir(config["spooldir"])
        for i in range(len(config["printer"])):
            args = (config["printer"][i]).split(",", maxsplit = 1)
            prn = args[1].strip()
            port = int(args[0].strip())
            p = printserver.print_server('', port, spooler.printer(prn))
            printserver.servers.append(p)
        #
        try:
            try:
                asyncore.loop(timeout = 4.0)
            except KeyboardInterrupt:
                pass
            #
        finally:
            print("Print Server Exit")
        #
    #

    def terminate(*args):
        for s in servers: s.handle_close()
    #

# class printserver

###########################################################################

print("start ...")

import sys, asyncore, os, signal

# configuration loading errors need to be handled before becoming a daemon
config = rpsconf.loadconfig()
if len(config["printer"]) == 0 :
    print("invalid config!")
    quit()
#

# set up our log file before daemonizing
# this will redirectly all output to log file only !!
#print("setuplog ...")
#printserver.setuplog(config["logfile"]) ## sys.stderr = sys.stdout = log

###########################################################################
# become a daemon task -- standard method

try:
    pid = os.fork()
except Exception as e:
    print(str(e))
    pid = -1
#

if pid == -1 :
    print("fork() not supported ...")
    printserver.chdir(config["spooldir"])
else :
    if (pid == 0): # child
        os.setsid()
        pid = os.fork()
        if (pid == 0): # child, final daemon process
            printserver.chdir(config["spooldir"])
        else:
            os._exit(0)
        #
    else:
        os._exit(0)
    #
    for fd in range(0, 2):
        try:
            os.close(fd)
        except OSError:
            pass
        #
    #
    # note that the Pythonic standard IO will be redirected below
    os.open("/dev/null", os.O_RDWR)
    os.dup2(0, 1)
    os.dup2(0, 2)
#

###########################################################################
# fire up the server task

print("\nRaw Print Server Startup: PID =", os.getpid())

# we want to clean up and finish the last jobs if we can
signal.signal(signal.SIGTERM, printserver.terminate)

printserver.mainloop(config)

###########################################################################
# end of file.
###########################################################################
