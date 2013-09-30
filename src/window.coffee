fsUtils = require './fs-utils'
path = require 'path'
telepath = require 'telepath'
$ = require './jquery-extensions'
_ = require './underscore-extensions'
remote = require 'remote'
ipc = require 'ipc'
WindowEventHandler = require './window-event-handler'

### Internal ###

windowEventHandler = null

# Schedule the window to be shown and focused on the next tick
#
# This is done in a next tick to prevent a white flicker from occurring
# if called synchronously.
displayWindow = ->
  _.nextTick ->
    atom.show()
    atom.focus()

# This method is called in any window needing a general environment, including specs
window.setUpEnvironment = (windowMode) ->
  atom.windowMode = windowMode
  window.resourcePath = atom.getLoadSettings().resourcePath
  atom.initialize()
  #TODO remove once all packages use the atom global
  window.config = atom.config
  window.syntax = atom.syntax
  window.pasteboard = atom.pasteboard
  window.keymap = atom.keymap

# Set up the default event handlers and menus for a non-editor windows.
#
# This can be used by packages to have a minimum level of keybindings and
# menus available when not using the standard editor window.
#
# This should only be called after setUpEnvironment() has been called.
window.setUpDefaultEvents = ->
  windowEventHandler = new WindowEventHandler
  keymap.loadBundledKeymaps()
  ipc.sendChannel 'update-application-menu', keymap.keystrokesByCommandForSelector('body')

# This method is only called when opening a real application window
window.startEditorWindow = ->
  installAtomCommand()
  installApmCommand()

  windowEventHandler = new WindowEventHandler
  restoreDimensions()
  config.load()
  keymap.loadBundledKeymaps()
  atom.themes.loadBaseStylesheets()
  atom.loadPackages()
  atom.loadThemes()
  deserializeEditorWindow()
  atom.activatePackages()
  keymap.loadUserKeymaps()
  atom.requireUserInitScript()
  ipc.sendChannel 'update-application-menu', keymap.keystrokesByCommandForSelector('body')
  $(window).on 'unload', ->
    $(document.body).hide()
    unloadEditorWindow()
    false

  displayWindow()

window.unloadEditorWindow = ->
  return if not project and not rootView
  windowState = atom.getWindowState()
  windowState.set('project', project.serialize())
  windowState.set('syntax', syntax.serialize())
  windowState.set('rootView', rootView.serialize())
  atom.deactivatePackages()
  windowState.set('packageStates', atom.packages.packageStates)
  atom.saveWindowState()
  rootView.remove()
  project.destroy()
  windowEventHandler?.unsubscribe()
  lessCache?.destroy()
  window.rootView = null
  window.project = null

installAtomCommand = (callback) ->
  commandPath = path.join(window.resourcePath, 'atom.sh')
  require('./command-installer').install(commandPath, callback)

installApmCommand = (callback) ->
  commandPath = path.join(window.resourcePath, 'node_modules', '.bin', 'apm')
  require('./command-installer').install(commandPath, callback)

window.onDrop = (e) ->
  e.preventDefault()
  e.stopPropagation()
  pathsToOpen = _.pluck(e.originalEvent.dataTransfer.files, 'path')
  atom.open({pathsToOpen}) if pathsToOpen.length > 0

window.deserializeEditorWindow = ->
  atom.deserializePackageStates()
  atom.deserializeProject()
  window.project = atom.project
  atom.deserializeRootView()
  window.rootView = atom.rootView

window.getDimensions = -> atom.getDimensions()

window.setDimensions = (args...) -> atom.setDimensions(args...)

window.restoreDimensions = (args...) -> atom.restoreDimensions(args...)

window.onerror = ->
  atom.openDevTools()

window.registerDeserializers = (args...) ->
  atom.deserializers.registerDeserializer(args...)
window.registerDeserializer = (args...) ->
  atom.deserializers.registerDeserializer(args...)
window.registerDeferredDeserializer = (args...) ->
  atom.deserializers.registerDeferredDeserializer(args...)
window.unregisterDeserializer = (args...) ->
  atom.deserializers.unregisterDeserializer(args...)
window.deserialize = (args...) ->
  atom.deserializers.deserialize(args...)
window.getDeserializer = (args...) ->
  atom.deserializer.getDeserializer(args...)

window.requireWithGlobals = (id, globals={}) ->
  existingGlobals = {}
  for key, value of globals
    existingGlobals[key] = window[key]
    window[key] = value

  require(id)

  for key, value of existingGlobals
    if value is undefined
      delete window[key]
    else
      window[key] = value

window.measure = (description, fn) ->
  start = new Date().getTime()
  value = fn()
  result = new Date().getTime() - start
  console.log description, result
  value

window.profile = (description, fn) ->
  measure description, ->
    console.profile(description)
    value = fn()
    console.profileEnd(description)
    value
