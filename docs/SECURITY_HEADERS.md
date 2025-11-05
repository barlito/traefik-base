# Security Headers - Detailed Guide

Complete documentation on security headers configured in Traefik.

## 📋 Configured Headers

Configuration in `traefik-dynamic.prod.yml` and `traefik-dynamic.local.yml`:

```yaml
security-headers:
  headers:
    frameDeny: true
    browserXssFilter: true
    contentTypeNosniff: true
    stsSeconds: 31536000
    stsIncludeSubdomains: true
    stsPreload: true
    customResponseHeaders:
      X-Powered-By: ""
      Server: ""
```

---

## 1. X-Frame-Options: DENY

### 🎯 Protection
Prevents your site from being embedded in an iframe.

### 🔴 Blocked Attack: Clickjacking
**Scenario**:
1. Attacker creates a malicious page
2. Embeds your site in an invisible iframe
3. Overlays fake buttons on top of your real buttons
4. User clicks thinking they're on the fake site, but actually clicks on your site

**Concrete Example**:
```html
<!-- Malicious site -->
<iframe src="https://traefik.barlito.fr" style="opacity: 0.0001"></iframe>
<button style="position: absolute; top: 100px">
  Click here to win $1000
</button>
<!-- User clicks and unknowingly executes an action on your dashboard -->
```

### ✅ With frameDeny
Browser refuses to load your site in the iframe.

### 🔧 Alternatives
```yaml
# Allow only your own domain
frameDeny: false
customFrameOptionsValue: "SAMEORIGIN"

# Allow specific domains
frameDeny: false
customFrameOptionsValue: "ALLOW-FROM https://trusted.com"
```

---

## 2. X-XSS-Protection: 1; mode=block

### 🎯 Protection
Activates the browser's built-in XSS filter.

### 🔴 Blocked Attack: Cross-Site Scripting (XSS)
**Scenario**:
```javascript
// Malicious URL
https://traefik.barlito.fr/search?q=<script>steal_cookies()</script>

// Without protection, the script executes
// With X-XSS-Protection, browser blocks execution
```

### ⚠️ Important Note
This header is **partially deprecated** but still useful for legacy browsers.
Modern browsers use **Content-Security-Policy** instead.

### 🔧 Possible Improvement
Add a proper CSP:
```yaml
customResponseHeaders:
  Content-Security-Policy: "default-src 'self'; script-src 'self' 'unsafe-inline'"
```

---

## 3. X-Content-Type-Options: nosniff

### 🎯 Protection
Forces browser to respect the declared `Content-Type`.

### 🔴 Blocked Attack: MIME Type Sniffing
**Scenario without protection**:
```
1. Attacker uploads "innocent.txt" containing JavaScript
2. Server returns Content-Type: text/plain
3. Browser "guesses" it's JS and executes it anyway
4. Malicious code executed
```

**With nosniff**:
```
1. Server says: "Content-Type: text/plain"
2. Browser strictly respects: treats as text
3. JavaScript not executed, attack failed
```

### 💡 Real Use Case
Protects against malicious uploads trying to masquerade as innocent files.

---

## 4. Strict-Transport-Security (HSTS)

### Complete Configuration
```yaml
stsSeconds: 31536000          # 1 year
stsIncludeSubdomains: true    # Apply to all subdomains
stsPreload: true              # HSTS preload list enrollment
```

Generates header:
```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
```

### 🎯 Protection
Forces browsers to **always** use HTTPS, even if user types `http://`.

### 🔴 Blocked Attack: SSL Stripping
**Attack scenario (without HSTS)**:
```
1. User types "traefik.barlito.fr" (without https://)
2. Browser tries http:// first
3. Attacker intercepts and stays in HTTP
4. Man-in-the-Middle successful, data stolen
```

**With HSTS**:
```
1. User visits once in HTTPS
2. HSTS header saved for 1 year
3. Future visits: browser forces HTTPS automatically
4. Even if user types http://, browser transforms to https:// BEFORE sending request
```

### ⚠️ includeSubDomains: Warning!
```yaml
stsIncludeSubdomains: true
```
**Means**: ALL your subdomains must support HTTPS.

If you have `old-app.barlito.fr` without HTTPS → **inaccessible for 1 year**!

### 🔒 HSTS Preload
```yaml
stsPreload: true
```

**What is it**: Hardcoded list in Chrome, Firefox, Safari, etc.
**Advantage**: Protection even on **first visit** (no need to have visited the site before)

**How to enroll**:
1. Configure `stsPreload: true` + 1 year minimum
2. Go to https://hstspreload.org/
3. Submit your domain
4. Wait a few weeks (inclusion in browsers)

**⚠️ WARNING: IRREVERSIBLE!**
- Removal from list = 6 to 12 months minimum
- All subdomains must support HTTPS forever
- Don't do it if you're not 100% sure

---

## 5. Server Information Hiding

```yaml
customResponseHeaders:
  X-Powered-By: ""    # Hide backend tech (PHP, Express, etc.)
  Server: ""          # Hide web server (nginx, apache)
```

### 🎯 Protection
Reduces attack surface by hiding technologies used.

### 🔴 Slowed Attack: Reconnaissance
**Without hiding**:
```http
HTTP/1.1 200 OK
Server: nginx/1.18.0 (Ubuntu)
X-Powered-By: PHP/7.4.3

→ Attacker knows: nginx 1.18.0, PHP 7.4.3
→ Searches for known exploits for these versions
```

**With hiding**:
```http
HTTP/1.1 200 OK
Server:
X-Powered-By:

→ Attacker must guess
→ Takes more time, may give up
```

### ⚠️ This is "Security by Obscurity"
This is **not real protection**, just an additional small barrier.
A determined attacker can still guess (error patterns, behaviors, etc.).

---

## 🧪 Testing Your Headers

### Online
- https://securityheaders.com/
- https://observatory.mozilla.org/

### CLI
```bash
curl -I https://traefik.barlito.fr | grep -E "(X-|Strict-Transport)"
```

### Expected Result
```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
X-XSS-Protection: 1; mode=block
```

---

## 🔧 Possible Optimizations

### Add Content-Security-Policy (CSP)
Modern protection against XSS, much more powerful than X-XSS-Protection.

```yaml
customResponseHeaders:
  Content-Security-Policy: >
    default-src 'self';
    script-src 'self' 'unsafe-inline' https://cdn.trusted.com;
    style-src 'self' 'unsafe-inline';
    img-src 'self' data: https:;
    font-src 'self' data:;
    connect-src 'self';
    frame-ancestors 'none';
    base-uri 'self';
    form-action 'self';
```

**Warning**: CSP can break your site if misconfigured. Test in `report-only` mode first:
```yaml
Content-Security-Policy-Report-Only: "default-src 'self'"
```

### Add Permissions-Policy
Controls browser APIs (geolocation, camera, microphone, etc.).

```yaml
customResponseHeaders:
  Permissions-Policy: >
    geolocation=(),
    microphone=(),
    camera=(),
    payment=(),
    usb=(),
    magnetometer=(),
    accelerometer=(),
    gyroscope=()
```

### Add Referrer-Policy
Controls information sent in the `Referer` header.

```yaml
customResponseHeaders:
  Referrer-Policy: "strict-origin-when-cross-origin"
```

---

## 📚 Resources

- [OWASP Secure Headers Project](https://owasp.org/www-project-secure-headers/)
- [MDN Web Security](https://developer.mozilla.org/en-US/docs/Web/Security)
- [HSTS Preload List](https://hstspreload.org/)
- [CSP Evaluator](https://csp-evaluator.withgoogle.com/)
