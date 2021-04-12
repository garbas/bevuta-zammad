{ stdenv
, lib
, fetchFromGitHub
, bundlerEnv
, defaultGemConfig
, callPackage
, writeText
, procps
, ruby
, postgresql
, mysql
, imlib2
, yarn
, yarn2nix-moretea
, v8
, srcOverride ? null
, depsDir ? ./.  # Should contain gemset.nix, yarn.nix and package.json.
}:

let

  pname = "zammad";
  version = "3.6.0";

  sourceDir = fetchFromGitHub (builtins.fromJSON (builtins.readFile ./source.json));

  databaseConfig = writeText "database.yml" ''
    production:
      url: <%= ENV['DATABASE_URL'] %>
  '';

  secretsConfig = writeText "secrets.yml" ''
    production:
      secret_key_base: <%= ENV['SECRET_KEY_BASE'] %>
  '';

  rubyEnv = bundlerEnv {
    name = "${pname}-gems-${version}";
    inherit version;

    # Which ruby version to select:
    #   https://docs.zammad.org/en/latest/prerequisites/software.html#ruby-programming-language
    inherit ruby;

    gemdir = sourceDir;
    gemset = depsDir + "/gemset.nix";
    groups = [
      # TODO: do we need all of the groups?
      "unicorn"   # server
      "nulldb"
      "test"
      "mysql"
      "puma"
      "development"
      "postgres"  # database
    ];
    gemConfig = defaultGemConfig // {
      pg = attrs: {
        buildFlags = [ "--with-pg-config=${postgresql}/bin/pg_config" ];
      };
      rszr = attrs: {
        buildInputs = [ imlib2 imlib2.dev ];
      };
      mini_racer = attrs: {
        buildFlags = [
          "--with-v8-dir=\"${v8}\""
        ];
        dontBuild = false;
        postPatch = ''
          substituteInPlace ext/mini_racer_extension/extconf.rb \
            --replace Libv8.configure_makefile '$CPPFLAGS += " -x c++"; Libv8.configure_makefile'
        '';
      };
    };
  };

  yarnEnv = yarn2nix-moretea.mkYarnPackage {
    pname = "${pname}-node-modules";
    inherit version;
    src = sourceDir;
    yarnLock = depsDir + "/yarn.lock";
    yarnNix = depsDir + "/yarn.nix";
    packageJSON = sourceDir + "/package.json";
  };

in stdenv.mkDerivation {
  name = "${pname}-${version}";
  inherit pname version;

  src = sourceDir;

  buildInputs = [
    rubyEnv
    rubyEnv.wrappedRuby
    rubyEnv.bundler
    yarn
    postgresql
    procps
  ];

  RAILS_ENV = "production";

  buildPhase = ''
    node_modules=${yarnEnv}/libexec/Zammad/node_modules
    ${yarn2nix-moretea.linkNodeModulesHook}

    # TODO: start postgresql on a file socket
    export PGDATA=$TMP/db
    export PGHOST=$TMP/socketdir
    export DATABASE_URL="postgresql:///test?host=$PGHOST"

    mkdir $PGDATA $PGHOST
    pg_ctl initdb
    echo "unix_socket_directories = '$PGHOST'" >> $PGDATA/postgresql.conf
    pg_ctl start &
    trap "pkill postgres || true" EXIT
    sleep 1
    psql -d postgres -c "create database test"

    rake assets:precompile

    psql -d postgres -c "drop database test"
    pg_ctl stop -m fast
  '';

  installPhase = ''
    mkdir -p $out/config
    cp -R ./* $out
    rm -R $out/tmp/*
    cp ${databaseConfig} $out/config/database.yml
    cp ${secretsConfig} $out/config/secrets.yml
    sed -i -e "s|info|debug|" $out/config/environments/production.rb
  '';

  passthru = {
    inherit rubyEnv yarnEnv;
    updateScript = callPackage ./update.nix {};
  };

  meta = with lib; {
    description = "Zammad, a web-based, open source user support/ticketing solution.";
    homepage = "https://zammad.org";
    license = licenses.agpl3Plus;
    platforms = [ "x86_64-linux" ];
    maintainers = with maintainers; [ garbas ];
  };
}
