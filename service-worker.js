'use strict';

var SHELL_CACHE = 'parrallery-shell-v1';
var AUDIO_CACHE = 'parallery-audio-v1';
var SHELL_FILES = [
  '/index.html',
  '/logo-white.svg',
  '/apple-touch-icon.png',
  '/share-default.png'
];

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(SHELL_CACHE)
      .then(function (cache) { return cache.addAll(SHELL_FILES); })
      .then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (names) {
      return Promise.all(names.map(function (name) {
        if (name.indexOf('parrallery-shell-') === 0 && name !== SHELL_CACHE) {
          return caches.delete(name);
        }
      }));
    }).then(function () { return self.clients.claim(); })
  );
});

function audioRangeResponse(response, request) {
  var range = request.headers.get('range');
  var match = range && /^bytes=(\d*)-(\d*)$/.exec(range.trim());
  if (!match) return Promise.resolve(response);

  return response.arrayBuffer().then(function (buffer) {
    var total = buffer.byteLength;
    var start = match[1] ? Number(match[1]) : Math.max(0, total - Number(match[2]));
    var end = match[2] ? Number(match[2]) : total - 1;
    if (start >= total || end < start) {
      return new Response(null, {
        status: 416,
        headers: { 'Content-Range': 'bytes */' + total }
      });
    }

    end = Math.min(end, total - 1);
    var headers = new Headers(response.headers);
    headers.set('Accept-Ranges', 'bytes');
    headers.set('Content-Range', 'bytes ' + start + '-' + end + '/' + total);
    headers.set('Content-Length', String(end - start + 1));
    headers.delete('Content-Encoding');
    return new Response(buffer.slice(start, end + 1), {
      status: 206,
      statusText: 'Partial Content',
      headers: headers
    });
  });
}

self.addEventListener('fetch', function (event) {
  var request = event.request;
  if (request.method !== 'GET') return;

  var url = new URL(request.url);
  if (request.destination === 'audio' || request.headers.has('range')) {
    event.respondWith(
      caches.open(AUDIO_CACHE).then(function (cache) {
        return cache.match(request, { ignoreVary: true }).then(function (cached) {
          if (cached) return audioRangeResponse(cached, request);
          return fetch(request);
        });
      })
    );
    return;
  }

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request).then(function (response) {
        if (response.ok) {
          var copy = response.clone();
          caches.open(SHELL_CACHE).then(function (cache) {
            return cache.put('/index.html', copy);
          }).catch(function (error) {
            console.warn('Could not update the offline app shell', error);
          });
        }
        return response;
      }).catch(function () {
        return caches.open(SHELL_CACHE).then(function (cache) {
          return cache.match('/index.html').then(function (cached) {
            return cached || new Response('The app is not available offline yet. Open it online once, then try again.', {
              status: 503,
              headers: { 'Content-Type': 'text/plain; charset=utf-8' }
            });
          });
        });
      })
    );
    return;
  }

  if (url.origin === self.location.origin) {
    event.respondWith(
      caches.open(SHELL_CACHE).then(function (cache) {
        return cache.match(request).then(function (cached) {
          if (cached) return cached;
          return fetch(request).then(function (response) {
            if (response.ok) cache.put(request, response.clone());
            return response;
          });
        });
      })
    );
  }
});
