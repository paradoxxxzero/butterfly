# (c) 2007 Chris AtLee <chris@atlee.ca>
# Licensed under the MIT license:
# http://www.opensource.org/licenses/mit-license.php
#
# Original author: Chris AtLee
#
# Modified by David Ford, 2011-12-6
# added py3 support and encoding
# added pam_end
# added pam_setcred to reset credentials after seeing Leon Walker's remarks
# added byref as well
# use readline to prestuff the getuser input
# Modified by Peter Cai, 2017-02-10
# interactive login for Butterfly

'''
PAM module for python
Provides an authenticate function that will allow the caller to authenticate
a user against the Pluggable Authentication Modules (PAM) on the system.
Implemented using ctypes, so no compilation is necessary.
'''

import os
import sys
from ctypes import (
    CDLL, CFUNCTYPE, POINTER, Structure, byref, c_char_p, c_int, c_size_t,
    c_void_p)
from ctypes.util import find_library


class PamHandle(Structure):
    """wrapper class for pam_handle_t pointer"""
    _fields_ = [("handle", c_void_p)]

    def __init__(self):
        Structure.__init__(self)
        self.handle = 0


class PamMessage(Structure):
    """wrapper class for pam_message structure"""
    _fields_ = [("msg_style", c_int), ("msg", c_char_p)]

    def __repr__(self):
        return "<PamMessage %i '%s'>" % (self.msg_style, self.msg)


class PamResponse(Structure):
    """wrapper class for pam_response structure"""
    _fields_ = [("resp", c_char_p), ("resp_retcode", c_int)]

    def __repr__(self):
        return "<PamResponse %i '%s'>" % (self.resp_retcode, self.resp)


conv_func = CFUNCTYPE(
    c_int, c_int, POINTER(POINTER(PamMessage)),
    POINTER(POINTER(PamResponse)), c_void_p)


class PamConv(Structure):
    """wrapper class for pam_conv structure"""
    _fields_ = [("conv", conv_func), ("appdata_ptr", c_void_p)]


# Various constants
PAM_PROMPT_ECHO_OFF = 1
PAM_PROMPT_ECHO_ON = 2
PAM_ERROR_MSG = 3
PAM_TEXT_INFO = 4
PAM_REINITIALIZE_CRED = 8

libc = CDLL(find_library("c"))
libpam = CDLL(find_library("pam"))
libpam_misc = CDLL(find_library("pam_misc"))

calloc = libc.calloc
calloc.restype = c_void_p
calloc.argtypes = [c_size_t, c_size_t]

pam_end = libpam.pam_end
pam_end.restype = c_int
pam_end.argtypes = [PamHandle, c_int]

pam_start = libpam.pam_start
pam_start.restype = c_int
pam_start.argtypes = [c_char_p, c_char_p, POINTER(PamConv), POINTER(PamHandle)]

pam_setcred = libpam.pam_setcred
pam_setcred.restype = c_int
pam_setcred.argtypes = [PamHandle, c_int]

pam_strerror = libpam.pam_strerror
pam_strerror.restype = c_char_p
pam_strerror.argtypes = [PamHandle, c_int]

pam_authenticate = libpam.pam_authenticate
pam_authenticate.restype = c_int
pam_authenticate.argtypes = [PamHandle, c_int]

misc_conv = libpam_misc.misc_conv


class PAM():
    code = 0
    reason = None

    def __init__(self):
        pass

    def authenticate(
            self, username,
            service='login', encoding='utf-8', resetcreds=True):
        """PAM authentication through standard input for the given service.
           Returns True for success, or False for failure.
           self.code (integer) and self.reason (string) are always stored
           and may be referenced for the reason why authentication failed.
           0/'Success' will be stored for success.
           Python3 expects bytes() for ctypes inputs.  This function will make
           necessary conversions using the supplied encoding.
        Inputs:
          username: username to authenticate
          service:  PAM service to authenticate against, defaults to 'login'
        Returns:
          success:  True
          failure:  False
        """

        # python3 ctypes prefers bytes
        if sys.version_info >= (3,):
            if isinstance(username, str):
                username = username.encode(encoding)
            if isinstance(service, str):
                service = service.encode(encoding)
        else:
            if isinstance(username, unicode):
                username = username.encode(encoding)
            if isinstance(service, unicode):
                service = service.encode(encoding)

        if b'\x00' in username or b'\x00' in service:
            self.code = 4  # PAM_SYSTEM_ERR in Linux-PAM
            self.reason = 'strings may not contain NUL'
            return False

        handle = PamHandle()
        conv = PamConv(conv_func(misc_conv), 0)
        retval = pam_start(service, username, byref(conv), byref(handle))

        if retval != 0:
            # This is not an authentication error,
            # something has gone wrong starting up PAM
            self.code = retval
            self.reason = "pam_start() failed"
            return False

        retval = pam_authenticate(handle, 0)
        auth_success = retval == 0

        if auth_success and resetcreds:
            retval = pam_setcred(handle, PAM_REINITIALIZE_CRED)

        # store information to inform the caller why we failed
        self.code = retval
        self.reason = pam_strerror(handle, retval)
        if sys.version_info >= (3,):
            self.reason = self.reason.decode(encoding)

        pam_end(handle, retval)

        return auth_success


def login_prompt(username, profile, env):
    pam = PAM()

    success = pam.authenticate(username, profile)
    print('{} {}'.format(pam.code, pam.reason))

    if success:
        su = '/usr/bin/su'
        if not os.path.exists(su):
            su = '/bin/su'
        os.execvpe(su, [su, '-l', username], env)
    return success


if __name__ == "__main__":
    if login_prompt(sys.argv[1], sys.argv[2], os.environ):
        exit(0)
    else:
        exit(1)
