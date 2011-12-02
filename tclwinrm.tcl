########################################################################
# Copyright 2011 Cloud Sidekick
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#########################################################################

package provide tclwinrm 1.0.2

package require Tcl 8.5
package require base64
package require tdom
package require uuid
package require http

namespace eval tclwinrm {
		variable url
		variable user
		variable pwd

		variable http_err_code
		dict set http_err_code 400 "Bad Request"
		dict set http_err_code 401 "Unauthorized - check user id, password and ensure that basic authorication is enabled"
		dict set http_err_code 402 "Payment Required"
		dict set http_err_code 403 "Forbidden"
		dict set http_err_code 404 "Not Found"
		dict set http_err_code 405 "Method Not Allowed"
		dict set http_err_code 406 "Not Acceptable"
		dict set http_err_code 407 "Proxy Authentication Required"
		dict set http_err_code 408 "Request Timeout"
		dict set http_err_code 409 "Conflict"
		dict set http_err_code 410 "Gone"
		dict set http_err_code 411 "Length Required"
		dict set http_err_code 412 "Precondition Failed"
		dict set http_err_code 413 "Request Entity Too Large"
		dict set http_err_code 414 "Request-url Too Long"
		dict set http_err_code 415 "Unsupported Media Type"
		dict set http_err_code 416 ""
		dict set http_err_code 417 "Expectation Failed"
		dict set http_err_code 500 "Internal Server Error"
		dict set http_err_code 501 "Not Implemented"
		dict set http_err_code 502 "Bad Gateway"
		dict set http_err_code 503 "Service Unavailable"
		dict set http_err_code 504 "Gateway Timeout"
		dict set http_err_code 505 "HTTP Version Not Supported"
}
proc tclwinrm::configure {protocol address port u p} {
		variable url
		variable user
		variable pwd
		set url $protocol://$address:$port
		set user $u
		set pwd $p
}
proc tclwinrm::Perform_query {url header soap timeout} {
        variable debug
	variable http_err_code
	set timeout [expr {$timeout * 1000}]
	catch {set token [::http::geturl $url/wsman -type "application/soap+xml;charset=UTF-8" -headers $header -timeout $timeout -query $soap]} error_code


        if {[string match "::http::*" $error_code] == 0} {
                if {[string match "error reading*software caused connection abort" $error_code]} {
                        return -code error -level 2 "error: Winrm endpoint refused connection. Verfiy that address, port and protocol (http or https) are valid.\012url:\012\012$url"
                } else {
			if {[string is integer $error_code]} {
				set err_msg [dict get $http_err_code $error_code]
			} else { 
				set err_msg ""
			}

			return -code error -level 2 "$error_code $err_msg\012url:\012\012$url"
                }
        }
        if {"[::http::status $token]" ne "ok" || [::http::ncode $token] != 200} {
		if {"[::http::ncode $token]" ne ""} {
			set err_msg [dict get $http_err_code [::http::ncode $token]]
		} else {
			set err_msg ""
		}
                return -code error -level 2 "error: [::http::status $token] [::http::code $token] $err_msg [::http::data $token]\012url:\012\012$url"
        } else {
                set body [::http::data $token]
        }

        if {[info exists token] == 1} {
                ::http::cleanup $token
        }
        if {$debug == 1} {
                puts "Return Body:\n$body"
        }
        return $body
}

proc tclwinrm::rshell {command {timeout 120} {debug_user 0}} {
	variable url
	variable user
	variable pwd
	variable debug
	
	set debug $debug_user
	set output_buffer ""
	
	set auth "Basic [base64::encode $user:$pwd]"
	lappend header Authorization $auth

	set soapEnv "<s:Envelope 
	  xmlns:s=\"http://www.w3.org/2003/05/soap-envelope\"
	  xmlns:wsa=\"http://schemas.xmlsoap.org/ws/2004/08/addressing\"
	  xmlns:wsman=\"http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd\">
	  <s:Header>
	    <wsa:To>
		$url/wsman
	    </wsa:To>
	    <wsman:ResourceURI s:mustUnderstand=\"true\">
	      http://schemas.microsoft.com/wbem/wsman/1/windows/shell/cmd
	    </wsman:ResourceURI>
	    <wsa:ReplyTo>
	      <wsa:Address s:mustUnderstand=\"true\">
		http://schemas.xmlsoap.org/ws/2004/08/addressing/role/anonymous
	      </wsa:Address>
	    </wsa:ReplyTo>
	    <wsa:Action s:mustUnderstand=\"true\">
	      http://schemas.xmlsoap.org/ws/2004/09/transfer/Create
	    </wsa:Action>
	    <wsman:MaxEnvelopeSize s:mustUnderstand=\"true\">153600</wsman:MaxEnvelopeSize>
	    <wsa:MessageID>uuid:[::uuid::uuid generate]</wsa:MessageID>
	    <wsman:Locale xml:lang=\"en-US\" s:mustUnderstand=\"false\" />
	    <wsman:OptionSet xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">
	      <wsman:Option Name=\"WINRS_NOPROFILE\">TRUE</wsman:Option>
	      <wsman:Option Name=\"WINRS_CODEPAGE\">437</wsman:Option>
	    </wsman:OptionSet>
	    <wsman:OperationTimeout>PT$timeout.000S</wsman:OperationTimeout>
	  </s:Header>
	  <s:Body>
	    <rsp:Shell xmlns:rsp=\"http://schemas.microsoft.com/wbem/wsman/1/windows/shell\">
	      <rsp:InputStreams>stdin</rsp:InputStreams>
	      <rsp:OutputStreams>stdout stderr</rsp:OutputStreams>
	    </rsp:Shell>
	  </s:Body>
	</s:Envelope>"

	set httpBody [tclwinrm::Perform_query $url $header $soapEnv $timeout]

	set xmldoc [dom parse $httpBody]
	set root [$xmldoc documentElement]
	set shell_node [$root selectNodes {//*[local-name()='Selector']}]
	set shell_id [$shell_node selectNodes string(.)]
	$root delete
	$xmldoc delete

	set soapEnv "<s:Envelope
	  xmlns:s=\"http://www.w3.org/2003/05/soap-envelope\"
	  xmlns:wsa=\"http://schemas.xmlsoap.org/ws/2004/08/addressing\"
	  xmlns:wsman=\"http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd\">
	  <s:Header>
	    <wsa:To>$url/wsman</wsa:To>
	    <wsman:ResourceURI s:mustUnderstand=\"true\">http://schemas.microsoft.com/wbem/wsman/1/windows/shell/cmd</wsman:ResourceURI>
	    <wsa:ReplyTo>
	      <wsa:Address s:mustUnderstand=\"true\">http://schemas.xmlsoap.org/ws/2004/08/addressing/role/anonymous</wsa:Address>
	    </wsa:ReplyTo>
	    <wsa:Action s:mustUnderstand=\"true\">http://schemas.microsoft.com/wbem/wsman/1/windows/shell/Command</wsa:Action>
	    <wsman:MaxEnvelopeSize s:mustUnderstand=\"true\">153600</wsman:MaxEnvelopeSize>
	    <wsa:MessageID>uuid:[::uuid::uuid generate]</wsa:MessageID>
	    <wsman:Locale xml:lang=\"en-US\" s:mustUnderstand=\"false\" />
	    <wsman:SelectorSet>
		<wsman:Selector Name=\"ShellId\">$shell_id</wsman:Selector>
	    </wsman:SelectorSet>
	    <wsman:OptionSet xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">
		<wsman:Option Name=\"WINRS_CONSOLEMODE_STDIN\">TRUE</wsman:Option>
		<wsman:Option Name=\"WINRS_SKIP_CMD_SHELL\">FALSE</wsman:Option>
	    </wsman:OptionSet>
	    <wsman:OperationTimeout>PT$timeout.000S</wsman:OperationTimeout>
	  </s:Header>
	  <s:Body>
	    <rsp:CommandLine xmlns:rsp=\"http://schemas.microsoft.com/wbem/wsman/1/windows/shell\">
		<rsp:Command>&quot;$command&quot;</rsp:Command>
	    </rsp:CommandLine>
	  </s:Body>
	</s:Envelope>"

	set httpBody [tclwinrm::Perform_query $url $header $soapEnv $timeout]

	if {$debug == 1} {
		puts $httpBody
	}
	set xmldoc [dom parse $httpBody]
	set root [$xmldoc documentElement]
	set cmd_id_node [$root selectNodes {//*[local-name()='CommandId']}]
	set command_id [$cmd_id_node selectNodes string(.)]
	$root delete
	$xmldoc delete

	set soapEnv "<s:Envelope 
	  xmlns:s=\"http://www.w3.org/2003/05/soap-envelope\"
	  xmlns:wsa=\"http://schemas.xmlsoap.org/ws/2004/08/addressing\"
	  xmlns:wsman=\"http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd\">
	  <s:Header>
	    <wsa:To>
		$url/wsman
	    </wsa:To>
	    <wsa:ReplyTo>
	      <wsa:Address s:mustUnderstand=\"true\">
		http://schemas.xmlsoap.org/ws/2004/08/addressing/role/anonymous
	      </wsa:Address>
	    </wsa:ReplyTo>
	    <wsa:Action s:mustUnderstand=\"true\">
	      http://schemas.microsoft.com/wbem/wsman/1/windows/shell/Receive
	    </wsa:Action>
	    <wsman:MaxEnvelopeSize s:mustUnderstand=\"true\">
	      153600
	    </wsman:MaxEnvelopeSize>
	    <wsa:MessageID>uuid:[::uuid::uuid generate]</wsa:MessageID>
	    <wsman:Locale xml:lang=\"en-US\" s:mustUnderstand=\"false\" />
	    <wsman:ResourceURI 
	      xmlns:wsman=\"http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd\">
	      http://schemas.microsoft.com/wbem/wsman/1/windows/shell/cmd
	    </wsman:ResourceURI>
	    <wsman:SelectorSet 
	      xmlns:wsman=\"http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd\"
	      xmlns=\"http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd\">
	      <wsman:Selector Name=\"ShellId\">$shell_id</wsman:Selector>
	    </wsman:SelectorSet>
	    <wsman:OperationTimeout>PT$timeout.000S</wsman:OperationTimeout>
	  </s:Header>
	  <s:Body>
	    <rsp:Receive 
	      xmlns:rsp=\"http://schemas.microsoft.com/wbem/wsman/1/windows/shell\"
	      SequenceId=\"0\">
	      <rsp:DesiredStream CommandId=\"$command_id\">
		stdout stderr
	      </rsp:DesiredStream>
	    </rsp:Receive>
	    </s:Body>
	</s:Envelope>"
	set exit_code ""

	while {1} {
		### we will keep checking the results until the command is done. 
		### any output we've received while the command is running we'll append to the result

		set httpBody [tclwinrm::Perform_query $url $header $soapEnv $timeout]

		if {$debug == 1} {
			puts $httpBody
		}
		set xmldoc [dom parse $httpBody]
		set root [$xmldoc documentElement]
		set states [$root selectNodes {//*[local-name()='CommandState']}]
		foreach state_node $states {
			set state [$state_node  getAttribute State]
			if {"$state" eq "http://schemas.microsoft.com/wbem/wsman/1/windows/shell/CommandState/Done"} {
				break
			}
		}
		set stream_nodes [$root selectNodes {//*[local-name()='Stream']}]
		if {"$state" eq "http://schemas.microsoft.com/wbem/wsman/1/windows/shell/CommandState/Done"} {
			set exit_codes [$root selectNodes {//*[local-name()='ExitCode']}]
			foreach exit_code_node $exit_codes {
				#walk to the last one
			}
			set exit_code [$exit_code_node selectNodes string(.)]
			break
		}
		foreach stream $stream_nodes {
			set output_buffer $output_buffer[::base64::decode [$stream selectNodes string(.)]]
		}
		$root delete
		$xmldoc delete
		after 1000
	}
	foreach stream $stream_nodes {
		set output_buffer $output_buffer[::base64::decode [$stream selectNodes string(.)]]
	}
	set soapEnv "<s:Envelope
	  xmlns:s=\"http://www.w3.org/2003/05/soap-envelope\"
	  xmlns:wsa=\"http://schemas.xmlsoap.org/ws/2004/08/addressing\"
	  xmlns:wsman=\"http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd\">
	  <s:Header>
	    <wsa:To>$url</wsa:To>
	    <wsa:ReplyTo>
	      <wsa:Address s:mustUnderstand=\"true\">
		http://schemas.xmlsoap.org/ws/2004/08/addressing/role/anonymous
	      </wsa:Address>
	    </wsa:ReplyTo>
	    <wsa:Action s:mustUnderstand=\"true\">
	      http://schemas.xmlsoap.org/ws/2004/09/transfer/Delete
	    </wsa:Action>
	    <wsman:MaxEnvelopeSize s:mustUnderstand=\"true\">153600</wsman:MaxEnvelopeSize>
	    <wsa:MessageID>uuid:[::uuid::uuid generate]</wsa:MessageID>
	    <wsman:Locale xml:lang=\"en-US\" s:mustUnderstand=\"false\" />
	    <wsman:ResourceURI 
	      xmlns:wsman=\"http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd\">
	      http://schemas.microsoft.com/wbem/wsman/1/windows/shell/cmd
	    </wsman:ResourceURI>
	    <wsman:SelectorSet 
	      xmlns:wsman=\"http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd\"
	      xmlns=\"http://schemas.dmtf.org/wbem/wsman/1/wsman.xsd\">
	      <wsman:Selector Name=\"ShellId\">$shell_id</wsman:Selector>
	    </wsman:SelectorSet>
	    <wsman:OperationTimeout>PT$timeout.000S</wsman:OperationTimeout>
	  </s:Header>
	  <s:Body></s:Body>
	</s:Envelope>"

	set httpBody [tclwinrm::Perform_query $url $header $soapEnv $timeout]

	# if it was a powerscript and it errored, let's clean it up a bit
	regsub -all "_x000D__x000A_" $output_buffer "" output_buffer
	regsub -all "&lt;" $output_buffer "<" output_buffer
	regsub -all "</S><S S=\"Error\">" $output_buffer "" output_buffer
	if {"$exit_code" eq "1"} {
		return -code error -level 1 "tclwinrm command error:\n$command\n$output_buffer"
	} else {
		return $output_buffer
	}
}
