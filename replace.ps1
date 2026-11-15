$content = Get-Content "C:/Users/ntuth/parallery/app.html" -Raw

# Add hamburger button and sidebar CSS
$css = @"
.hamburger-btn{position:relative;z-index:10;display:flex;align-items:center;justify-content:center;width:44px;height:44px;border-radius:14px;background:var(--pr-bg-2);border:1px solid var(--pr-line);color:var(--pr-silver);cursor:pointer;transition:background .15s ease,color .15s ease}
.hamburger-btn:hover{background:rgba(255,255,255,.06);color:var(--pr-silver-hi)}
.hamburger-btn svg{width:22px;height:22px}
.sidebar-overlay{position:fixed;inset:0;z-index:80;background:rgba(0,0,0,.55);backdrop-filter:blur(8px);opacity:0;pointer-events:none;transition:opacity .22s ease}
.sidebar-overlay.is-visible{opacity:1;pointer-events:auto}
.sidebar{position:fixed;top:0;right:0;bottom:0;z-index:90;width:84%;max-width:320px;max-width:80vw;display:flex;flex-direction:column;background:var(--pr-bg);border-left:1px solid var(--pr-line);box-shadow:-8px 0 24px rgba(0,0,0,.4);transform:translateX(100%);transition:transform .26s cubic-bezier(.22,.8,.24,1);backdrop-filter:blur(20px)}
.sidebar.is-open{transform:translateX(0)}
.sidebar-header{display:flex;align-items:center;justify-content:space-between;padding:20px 22px;border-bottom:1px solid var(--pr-line)}
.sidebar-title{font-size:16px;font-weight:800;color:var(--pr-silver-hi);letter-spacing:-.3px}
.sidebar-close{width:36px;height:36px;border-radius:12px;background:none;border:0;cursor:pointer;color:var(--pr-grey);transition:background .15s ease,color .15s ease}
.sidebar-close:hover{background:rgba(255,255,255,.06);color:var(--pr-silver-hi)}
.sidebar-nav{display:flex;flex-direction:column;gap:2px;padding:12px 16px}
.sidebar-item{display:flex;align-items:center;gap:14px;padding:14px 16px;border-radius:14px;color:var(--pr-silver);text-decoration:none;transition:background .15s ease,color .15s ease;font-family:inherit;font-size:14px;font-weight:600}
.sidebar-item:hover{background:rgba(255,255,255,.07);color:var(--pr-silver-hi)}
.sidebar-item svg{width:22px;height:22px;flex-shrink:0}
.sidebar-divider{height:1px;background:var(--pr-line);margin:12px 16px}
.sidebar-item svg{color:var(--pr-grey)}
.sidebar-item:hover svg{color:var(--pr-silver-hi)}
"@

$content = $content -replace '(?s)(\.home-top\b.*?\.count-badge\{.*?\})', "`$1`n$css"

$content | Set-Content "C:/Users/ntuth/parillery/app.html" -Force
Write-Host "Done"