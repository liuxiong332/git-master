var gulp = require('gulp');
var spawn = require('cross-spawn-async');
var path = require('path');
var packager = require('electron-packager');
var coffee = require('gulp-coffee');
var babel = require('gulp-babel');
var gutil = require('gulp-util');

function runNpmCmd(cmdName, args, callback) {
  if (process.platform === 'win32') cmdName += '.cmd';
  var cmdPath = path.resolve(__dirname, './node_modules/.bin/' + cmdName);
  var childProcess = spawn(cmdPath, args, {stdio: 'inherit', cwd: __dirname});
  childProcess.on('close', function (code) {
    code === 0 ? callback(null) : callback('process exit with code ' + code);
  });
}

gulp.task('pack-all', function(done) {
  packager({
    arch: 'all',
    dir: path.resolve(__dirname, 'app/'),
    platform: 'all',
    'app-bundle-id': 'git-master',
    'app-category-type': 'public.app-category.developer-tools',
    'app-version': '0.0',
    asar: true,
    version: '0.36.7'
  }, function done (err, appPath) {
    done(err);
  });
});

gulp.task('pack', function(done) {
  packager({
    arch: 'x64',
    dir: path.resolve(__dirname, 'app/'),
    platform: 'win32',
    version: '0.36.7'
  }, function(err, appPath) {
    done(err);
  });
});

gulp.task('start', function(done) {
  runNpmCmd('electron', ['./dist/browser/main.js', '--enable-logging'], done);
});

gulp.task('start-dev', function(done) {
  runNpmCmd('electron', ['./dist/browser/main.js', '--enable-logging', '-r', __dirname], done);
});

gulp.task('coffee', function() {
  gulp.src('./src/**/*.coffee')
    .pipe(coffee({bare: true}).on('error', gutil.log))
    .pipe(gulp.dest('./dist/'));
});

gulp.task('babel', function() {
  gulp.src('./src/**/*.js')
    .pipe(babel({
      presets: ['es2015']
    }))
    .pipe(gulp.dest('./dist/'))
});

gulp.task('electron-rebuild', function(done) {
  runNpmCmd('electron-rebuild', [], done);
});

gulp.task('compile', ['coffee', 'babel']);
