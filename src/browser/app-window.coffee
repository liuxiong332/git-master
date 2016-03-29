{BrowserWindow, app, dialog} = require 'electron'
path = require 'path'
fs = require 'fs'
url = require 'url'
_ = require 'underscore-plus'
{EventEmitter} = require 'events'

module.exports =
class AppWindow
  _.extend @prototype, EventEmitter.prototype

  @iconPath: path.resolve(__dirname, '..', '..', 'resources', 'app.png')
  @includeShellLoadTime: true

  browserWindow: null
  loaded: null
  isSpec: null

  constructor: (settings={}) ->
    {@resourcePath, initialPaths, pathToOpen, locationsToOpen, @isSpec, @headless, @safeMode, @devMode} = settings
    locationsToOpen ?= [{pathToOpen}] if pathToOpen
    locationsToOpen ?= []

    options =
      show: true
      title: 'Git Master'
      'web-preferences':
        'direct-write': true

    if @isSpec
      options['web-preferences']['page-visibility'] = true

    # Don't set icon on Windows so the exe's ico will be used as window and
    # taskbar's icon. See https://github.com/atom/atom/issues/4811 for more.
    if process.platform is 'linux'
      options.icon = @constructor.iconPath

    @browserWindow = new BrowserWindow options
    global.application.addWindow(this)

    @handleEvents()

    loadSettings = _.extend({}, settings)
    loadSettings.appVersion = app.getVersion()
    loadSettings.resourcePath = @resourcePath
    loadSettings.devMode ?= false
    loadSettings.safeMode ?= false
    loadSettings.appHome = process.env.APP_HOME
    loadSettings.clearWindowState ?= false
    loadSettings.initialPaths ?=
      for {pathToOpen} in locationsToOpen when pathToOpen
        if fs.statSyncNoException(pathToOpen).isFile?()
          path.dirname(pathToOpen)
        else
          pathToOpen

    loadSettings.initialPaths.sort()

    # Only send to the first non-spec window created
    if @constructor.includeShellLoadTime and not @isSpec
      @constructor.includeShellLoadTime = false
      loadSettings.shellLoadTime ?= Date.now() - global.shellStartTime

    @browserWindow.loadSettings = loadSettings

    @browserWindow.once 'window:loaded', =>
      @emit 'window:loaded'
      @loaded = true

    @setLoadSettings(loadSettings)
    @browserWindow.focusOnWebView() if @isSpec
    @browserWindow.temporaryState = {windowDimensions} if windowDimensions?

    hasPathToOpen = not (locationsToOpen.length is 1 and not locationsToOpen[0].pathToOpen?)
    @openLocations(locationsToOpen) if hasPathToOpen and not @isSpecWindow()

  setLoadSettings: (loadSettings) ->
    @browserWindow.loadURL url.format
      protocol: 'file'
      pathname: "#{@resourcePath}/static/index.html"
      slashes: true
      hash: encodeURIComponent(JSON.stringify(loadSettings))
    @browserWindow.webContents.openDevTools();

  getLoadSettings: ->
    if @browserWindow.webContents? and not @browserWindow.webContents.isLoading()
      hash = url.parse(@browserWindow.webContents.getURL()).hash.substr(1)
      JSON.parse(decodeURIComponent(hash))

  hasProjectPath: -> @getLoadSettings().initialPaths?.length > 0

  setupContextMenu: ->
    # ContextMenu = require './context-menu'
    #
    # @browserWindow.on 'context-menu', (menuTemplate) =>
    #   new ContextMenu(menuTemplate, this)

  containsPaths: (paths) ->
    for pathToCheck in paths
      return false unless @containsPath(pathToCheck)
    true

  containsPath: (pathToCheck) ->
    @getLoadSettings()?.initialPaths?.some (projectPath) ->
      if not projectPath
        false
      else if not pathToCheck
        false
      else if pathToCheck is projectPath
        true
      else if fs.statSyncNoException(pathToCheck).isDirectory?()
        false
      else if pathToCheck.indexOf(path.join(projectPath, path.sep)) is 0
        true
      else
        false

  handleEvents: ->
    @browserWindow.on 'close', ->
      global.application.saveState(false)

    @browserWindow.on 'closed', =>
      global.application.removeWindow(this)

    @browserWindow.on 'unresponsive', =>
      return if @isSpec

      chosen = dialog.showMessageBox @browserWindow,
        type: 'warning'
        buttons: ['Close', 'Keep Waiting']
        message: 'Editor is not responding'
        detail: 'The editor is not responding. Would you like to force close it or just keep waiting?'
      @browserWindow.destroy() if chosen is 0

    @browserWindow.webContents.on 'crashed', =>
      global.atomApplication.exit(100) if @headless

      chosen = dialog.showMessageBox @browserWindow,
        type: 'warning'
        buttons: ['Close Window', 'Reload', 'Keep It Open']
        message: 'The editor has crashed'
        detail: 'Please report this issue to https://github.com/atom/atom'
      switch chosen
        when 0 then @browserWindow.destroy()
        when 1 then @browserWindow.reload()

    @browserWindow.webContents.on 'will-navigate', (event, url) =>
      unless url is @browserWindow.webContents.getURL()
        event.preventDefault()

    @setupContextMenu()

    if @isSpec
      # Workaround for https://github.com/atom/atom-shell/issues/380
      # Don't focus the window when it is being blurred during close or
      # else the app will crash on Windows.
      if process.platform is 'win32'
        @browserWindow.on 'close', => @isWindowClosing = true

      # Spec window's web view should always have focus
      @browserWindow.on 'blur', =>
        @browserWindow.focusOnWebView() unless @isWindowClosing

  openPath: (pathToOpen, initialLine, initialColumn) ->
    @openLocations([{pathToOpen, initialLine, initialColumn}])

  openLocations: (locationsToOpen) ->
    if @loaded
      @sendMessage 'open-locations', locationsToOpen
    else
      @browserWindow.once 'window:loaded', => @openLocations(locationsToOpen)

  sendMessage: (message, detail) ->
    @browserWindow.webContents.send 'message', message, detail

  sendCommand: (command, args...) ->
    if @isSpecWindow()
      unless global.atomApplication.sendCommandToFirstResponder(command)
        switch command
          when 'window:reload' then @reload()
          when 'window:toggle-dev-tools' then @toggleDevTools()
          when 'window:close' then @close()
    else if @isWebViewFocused()
      @sendCommandToBrowserWindow(command, args...)
    else
      unless global.atomApplication.sendCommandToFirstResponder(command)
        @sendCommandToBrowserWindow(command, args...)

  sendCommandToBrowserWindow: (command, args...) ->
    action = if args[0]?.contextCommand then 'context-command' else 'command'
    @browserWindow.webContents.send action, command, args...

  getDimensions: ->
    [x, y] = @browserWindow.getPosition()
    [width, height] = @browserWindow.getSize()
    {x, y, width, height}

  close: -> @browserWindow.close()

  focus: -> @browserWindow.focus()

  minimize: -> @browserWindow.minimize()

  maximize: -> @browserWindow.maximize()

  restore: -> @browserWindow.restore()

  handlesAtomCommands: ->
    not @isSpecWindow() and @isWebViewFocused()

  isFocused: -> @browserWindow.isFocused()

  isMaximized: -> @browserWindow.isMaximized()

  isMinimized: -> @browserWindow.isMinimized()

  isWebViewFocused: -> @browserWindow.isWebViewFocused()

  isSpecWindow: -> @isSpec

  reload: -> @browserWindow.reload()

  toggleDevTools: -> @browserWindow.toggleDevTools()