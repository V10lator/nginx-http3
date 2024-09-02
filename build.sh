set -e

cd /github/home
echo Install dependencies.
echo deb http://deb.debian.org/debian trixie-backports main >> /etc/apt/sources.list
dpkg --add-architecture arm64
apt-get update
apt-get install --allow-change-held-packages --allow-downgrades --allow-remove-essential \
-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -fy \
cmake git libmaxminddb-dev wget libssl-dev libpcre2-dev zlib1g-dev build-essential crossbuild-essential-arm64

CFLAGS="-mcpu=neoverse-n1+crc+crypto -ftree-vectorize -ftree-slp-vectorize -mtls-dialect=gnu2 -pipe -fno-ident -flto=8 -fdevirtualize-at-ltrans -Wno-error"
CXXFLAGS="${CFLAGS} -fomit-frame-pointer"
export CFLAGS
export CXXFLAGS

wget -O /etc/apt/trusted.gpg.d/nginx_signing.asc https://nginx.org/keys/nginx_signing.key
echo deb-src https://nginx.org/packages/mainline/debian bookworm nginx \
>> /etc/apt/sources.list
echo -e 'Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900' \
> /etc/apt/preferences.d/99nginx
apt-get update
apt-get build-dep --allow-change-held-packages --allow-downgrades --allow-remove-essential \
-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -fy -aarm64 \
nginx
echo Fetch NGINX source code.
apt-get source nginx
echo Fetch quictls source code.
cd nginx-*
mkdir debian/modules
cd debian/modules
git clone --depth 1 --recursive https://github.com/quictls/openssl 
echo Fetch additional dependencies.
git clone --depth 1 --recursive https://github.com/google/ngx_brotli
mkdir ngx_brotli/deps/brotli/out
cd ngx_brotli/deps/brotli/out
#cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=installed ..
#cmake --build . --config Release --target brotlienc
cd ../../../..
git clone --depth 1 --recursive https://github.com/leev/ngx_http_geoip2_module
git clone --depth 1 --recursive https://github.com/openresty/headers-more-nginx-module
git clone --depth 1 --recursive https://github.com/aperezdc/ngx-fancyindex
echo Build nginx.
cd ..
sed -i 's|NGINX Packaging <nginx-packaging@f5.com>|V10lator <v10lator@myway.de>|g' control
sed -i 's|export DEB_CFLAGS_MAINT_APPEND=.*|export DEB_CFLAGS_MAINT_APPEND=|g' rules
sed -i 's|export DEB_LDFLAGS_MAINT_APPEND=.*|export DEB_LDFLAGS_MAINT_APPEND=|g' rules
sed -i 's|CFLAGS=""|CFLAGS="${CFLAGS}"|g' rules
sed -i 's|CXXFLAGS=""|CXXFLAGS="${CXXFLAGS}"|g' rules
sed -i 's|--sbin-path=/usr/sbin/nginx|--sbin-path=/usr/sbin/nginx --add-module=$(CURDIR)/debian/modules/ngx_brotli --add-module=$(CURDIR)/debian/modules/ngx_http_geoip2_module --add-module=$(CURDIR)/debian/modules/headers-more-nginx-module --add-module=$(CURDIR)/debian/modules/ngx-fancyindex|g' rules
sed -i 's|--http-scgi-temp-path=/var/cache/nginx/scgi_temp --user=nginx --group=nginx|--user=www-data --group=www-data|g' rules
sed -i 's|--with-compat||g' rules
sed -i 's|--with-http_addition_module --with-http_auth_request_module --with-http_dav_module --with-http_flv_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_mp4_module --with-http_random_index_module --with-http_realip_module --with-http_secure_link_module --with-http_slice_module --with-http_ssl_module --with-http_stub_status_module --with-http_sub_module|--with-http_auth_request_module --with-http_dav_module --with-http_flv_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_ssl_module --with-http_stub_status_module|g' rules
sed -i 's|--with-mail --with-mail_ssl_module --with-stream --with-stream_realip_module --with-stream_ssl_module --with-stream_ssl_preread_module|--with-pcre-jit --with-stream --with-stream_realip_module --with-stream_ssl_module --with-stream_ssl_preread_module --without-select_module --without-poll_module --without-http_browser_module --without-http_charset_module --without-http_empty_gif_module --without-http_limit_conn_module --without-http_memcached_module --without-http_mirror_module --without-http_split_clients_module --without-http_upstream_hash_module --without-http_upstream_ip_hash_module --without-http_upstream_keepalive_module --without-http_upstream_least_conn_module --without-http_upstream_random_module --without-http_upstream_zone_module --with-openssl=$(CURDIR)/debian/modules/openssl|g' rules
cd ..
CONFIG_SITE=/etc/dpkg-cross/cross-config.amd64 DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage aarm64 -Pcross,nocheck
cd ..
cp nginx_*.deb nginx.deb
hash=$(sha256sum nginx.deb | awk '{print $1}')
patch=$(cat /github/workspace/patch)
minor=$(cat /github/workspace/minor)
if [[ $hash != $(cat /github/workspace/hash) ]]; then
  echo $hash > /github/workspace/hash
  if [[ $GITHUB_EVENT_NAME == push ]]; then
    patch=0
    minor=$(($(cat /github/workspace/minor)+1))
    echo $minor > /github/workspace/minor
  else
    patch=$(($(cat /github/workspace/patch)+1))
  fi
  echo $patch > /github/workspace/patch
  change=1
  echo This is a new version.
else
  echo This is an old version.
fi
echo -e "hash=$hash\npatch=$patch\nminor=$minor\nchange=$change" >> $GITHUB_ENV
