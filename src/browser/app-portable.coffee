fs = require 'fs-plus'
path = require 'path'
{ipcMain} = require 'electron'

module.exports =
class AppPortable
  @getPortableAppHomePath: ->
    execDirectoryPath = path.dirname(process.execPath)
    path.join(execDirectoryPath, '..', '.git-master')

  @setPortable: (existingAppHome) ->
    fs.copySync(existingAppHome, @getPortableAppHomePath())

  @isPortableInstall: (platform, environmentAppHome, defaultHome) ->
    return false unless platform in ['linux', 'win32']
    return false if environmentAppHome
    return false if not fs.existsSync(@getPortableAppHomePath())
    # currently checking only that the directory exists  and is writable,
    # probably want to do some integrity checks on contents in future
    @isPortableAppHomePathWritable(defaultHome)

  @isPortableAppHomePathWritable: (defaultHome) ->
    writable = false
    message = ""
    try
      writePermissionTestFile = path.join(@getPortableAppHomePath(), "write.test")
      fs.writeFileSync(writePermissionTestFile, "test") if not fs.existsSync(writePermissionTestFile)
      fs.removeSync(writePermissionTestFile)
      writable = true
    catch error
      message = "Failed to use portable Atom home directory (#{@getPortableAppHomePath()}).  Using the default instead (#{defaultHome}).  #{error.message}"

    ipcMain.on 'check-portable-home-writable', (event) ->
      event.sender.send 'check-portable-home-writable-response', {writable, message}
    writable
