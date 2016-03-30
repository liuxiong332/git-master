global.shellStartTime = Date.now()

process.on 'uncaughtException', (error={}) ->
  console.log(error.message) if error.message?
  console.log(error.stack) if error.stack?

{app} = require 'electron'
fs = require 'fs-plus'
path = require 'path'
temp = require 'temp'
yargs = require 'yargs'
console.log = require 'nslog'

start = ->
  args = parseCommandLine()
  setupAppHome(args)
  setupCompileCache()
  # return if handleStartupEventWithSquirrel()

  # NB: This prevents Win10 from showing dupe items in the taskbar
  app.setAppUserModelId('com.squirrel.atom.atom')

  addPathToOpen = (event, pathToOpen) ->
    event.preventDefault()
    args.pathsToOpen.push(pathToOpen)

  addUrlToOpen = (event, urlToOpen) ->
    event.preventDefault()
    args.urlsToOpen.push(urlToOpen)

  app.on 'open-file', addPathToOpen
  app.on 'open-url', addUrlToOpen
  app.on 'will-finish-launching', setupCrashReporter

  if args.userDataDir?
    app.setPath('userData', args.userDataDir)
  else if args.test
    app.setPath('userData', temp.mkdirSync('git-master-test-data'))

  app.on 'ready', ->
    app.removeListener 'open-file', addPathToOpen
    app.removeListener 'open-url', addUrlToOpen

    AppApplication = require path.join(args.resourcePath, 'src', 'browser', 'application')
    AppApplication.open(args)

    console.log("App load time: #{Date.now() - global.shellStartTime}ms") unless args.test

normalizeDriveLetterName = (filePath) ->
  if process.platform is 'win32'
    filePath.replace /^([a-z]):/, ([driveLetter]) -> driveLetter.toUpperCase() + ":"
  else
    filePath

handleStartupEventWithSquirrel = ->
  return false unless process.platform is 'win32'
  SquirrelUpdate = require './squirrel-update'
  squirrelCommand = process.argv[1]
  SquirrelUpdate.handleStartupEvent(app, squirrelCommand)

setupCrashReporter = ->
  # crashReporter.start(productName: 'Atom', companyName: 'GitHub', submitURL: 'http://54.249.141.255:1127/post')

setupAppHome = ({setPortable}) ->
  return if process.env.APP_HOME

  gitMasterHome = path.join(app.getPath('home'), '.git-master')
  try
    gitMasterHome = fs.realpathSync(gitMasterHome)

  AppPortable = require './app-portable'

  if setPortable and not AppPortable.isPortableInstall(process.platform, process.env.APP_HOME, gitMasterHome)
    try
      AppPortable.setPortable(gitMasterHome)
    catch error
      console.log("Failed copying portable directory '#{gitMasterHome}' to '#{AppPortable.getPortableAppHomePath()}'")
      console.log("#{error.message} #{error.stack}")

  if AppPortable.isPortableInstall(process.platform, process.env.APP_HOME, gitMasterHome)
    gitMasterHome = AppPortable.getPortableAppHomePath()

  try
    atomHome = fs.realpathSync(atomHome)

  process.env.APP_HOME = gitMasterHome

setupCompileCache = ->
  compileCache = require('../compile-cache')
  compileCache.setAppHomeDirectory(process.env.APP_HOME)

writeFullVersion = ->
  process.stdout.write """
    Atom    : #{app.getVersion()}
    Electron: #{process.versions.electron}
    Chrome  : #{process.versions.chrome}
    Node    : #{process.versions.node}

  """

parseCommandLine = ->
  version = app.getVersion()
  options = yargs(process.argv[1..]).wrap(100)
  options.usage """
    Git Master v#{version}

    Usage: GitMaster [options] [path ...]

    One or more paths to files or folders may be specified. If there is an
    existing app window that contains all of the given folders, the paths
    will be opened in that window. Otherwise, they will be opened in a new
    window.

    Environment Variables:

      APP_DEV_RESOURCE_PATH  The path from which app loads source code in dev mode.
                              Defaults to `~/git-master/src`.

      APP_HOME               The root path for all configuration files and folders.
                              Defaults to `~/.git-master`.
  """
  options.alias('d', 'dev').boolean('d').describe('d', 'Run in development mode.')
  options.alias('f', 'foreground').boolean('f').describe('f', 'Keep the browser process in the foreground.')
  options.alias('h', 'help').boolean('h').describe('h', 'Print this usage message.')
  options.alias('l', 'log-file').string('l').describe('l', 'Log all output to file.')
  options.alias('n', 'new-window').boolean('n').describe('n', 'Open a new window.')
  options.boolean('profile-startup').describe('profile-startup', 'Create a profile of the startup execution time.')
  options.alias('r', 'resource-path').string('r').describe('r', 'Set the path to the git-master source directory and enable dev-mode.')
  options.boolean('portable').describe('portable', 'Set portable mode. Copies the ~/.git-master folder to be a sibling of the installed app location if a .git-master folder is not already there.')
  options.alias('t', 'test').boolean('t').describe('t', 'Run the specified specs and exit with error code on failures.')
  options.string('timeout').describe('timeout', 'When in test mode, waits until the specified time (in minutes) and kills the process (exit code: 130).')
  options.alias('v', 'version').boolean('v').describe('v', 'Print the version information.')
  options.alias('w', 'wait').boolean('w').describe('w', 'Wait for window to be closed before returning.')
  options.alias('a', 'add').boolean('a').describe('add', 'Open path as a new project in last used window.')
  options.string('socket-path')
  options.string('user-data-dir')
  options.boolean('clear-window-state').describe('clear-window-state', 'Delete all GitMaster environment state.')

  args = options.argv

  if args.help
    process.stdout.write(options.help())
    process.exit(0)

  if args.version
    writeFullVersion()
    process.exit(0)

  addToLastWindow = args['add']
  executedFrom = args['executed-from']?.toString() ? process.cwd()
  devMode = args['dev']
  safeMode = args['safe']
  pathsToOpen = args._
  test = args['test']
  timeout = args['timeout']
  newWindow = args['new-window']
  pidToKillWhenClosed = args['pid'] if args['wait']
  logFile = args['log-file']
  socketPath = args['socket-path']
  userDataDir = args['user-data-dir']
  profileStartup = args['profile-startup']
  clearWindowState = args['clear-window-state']
  urlsToOpen = []
  devResourcePath = process.env.APP_DEV_RESOURCE_PATH ? path.join(app.getPath('home'), 'git-master', 'src')
  setPortable = args.portable

  if args['resource-path']
    devMode = true
    resourcePath = args['resource-path']

  devMode = true if test
  resourcePath ?= devResourcePath if devMode

  unless fs.statSyncNoException(resourcePath)
    resourcePath = path.dirname(path.dirname(__dirname))

  # On Yosemite the $PATH is not inherited by the "open" command, so we have to
  # explicitly pass it by command line, see http://git.io/YC8_Ew.
  process.env.PATH = args['path-environment'] if args['path-environment']

  resourcePath = normalizeDriveLetterName(resourcePath)
  devResourcePath = normalizeDriveLetterName(devResourcePath)

  {resourcePath, devResourcePath, pathsToOpen, urlsToOpen, executedFrom, test,
   version, pidToKillWhenClosed, devMode, safeMode, newWindow,
   logFile, socketPath, userDataDir, profileStartup, timeout, setPortable,
   clearWindowState, addToLastWindow}

start()
