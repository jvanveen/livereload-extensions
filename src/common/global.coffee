# LRClient = require 'livereload-client'

ExtVersion = require('./version')

Status =
  unavailable:
    buttonEnabled: no
    buttonToolTip: 'LiveReload not available on this tab'
    buttonIcon: 'IconUnavailable.png'
    buttonIconHiRes: 'IconUnavailable@2x.png'
  disabled:
    buttonEnabled: yes
    buttonToolTip: 'Enable LiveReload'
    buttonIcon: 'IconDisabled.png'
    buttonIconHiRes: 'IconDisabled@2x.png'
  enabled:
    buttonEnabled: yes
    buttonToolTip: 'LiveReload is connecting, click to disable'
    buttonIcon: 'IconEnabled.png'
    buttonIconHiRes: 'IconEnabled@2x.png'
  active:
    buttonEnabled: yes
    buttonToolTip: 'LiveReload is connected, click to disable'
    buttonIcon: 'IconActive.png'
    buttonIconHiRes: 'IconActive@2x.png'



class TabState
  constructor: (@tab) ->
    @enabled = no
    @active  = no

  enable: ->
    @send 'enable', { @useFallback, scriptURI: @bundledScriptURI(), host: LiveReloadGlobal.host, port: LiveReloadGlobal.port }

  disable: ->
    @send 'disable'

  updateStatus: (status) ->
    if status.initial
      if !status.enabled
        @active = no
        if @enabled
          @enable()
        return
    if status.enabled?
      @enabled = status.enabled
    if status.active?
      @active = status.active

  status: ->
    switch
      when @active
        Status.active
      when @enabled
        Status.enabled
      else
        Status.disabled

  alert: (message) ->
    @send 'alert', message


if navigator.userAgent.match(/Mac OS X/)
  CannotConnectAlert = """Could not connect to LiveReload server. Please make sure that LiveReload 2.3 (or later) or another compatible server is running."""
else
  CannotConnectAlert = """Could not connect to LiveReload server. Please make sure that a compatible LiveReload server is running. (We recommend guard-livereload, until LiveReload 2 comes to your platform.)"""


TheWebSocket = (WebSocket ? MozWebSocket)


LiveReloadGlobal =
  _tabs: []

  initialize: ->
    chrome.storage.sync.get {https: false, hostname: '127.0.0.1', port: '35729'}, (items) =>
      @host = items.hostname
      @port = items.port
      console.debug('Using hostname:', @host)
      console.debug('Using port:', @port)

  killZombieTabs: ->
    @_tabs = (tabState for tabState in @_tabs when @isAvailable(tabState.tab))

  killZombieTab: (tab) ->
    for tabState, index in @_tabs
      if tabState.tab is tab
        @_tabs.splice index, 1
        return
    return

  findState: (tab, create=no) ->
    for tabState in @_tabs
      return tabState if tabState.tab is tab
    if create
      state = new TabState(tab)
      @_tabs.push state
      state
    else
      null

  toggle: (tab) ->
    if @isAvailable(tab)
      state = @findState(tab, yes)
      if state.enabled
        state.disable()
        unless @areAnyTabsEnabled()
          @afterDisablingLast()
      else
        if @areAnyTabsEnabled()
          state.useFallback = @useFallback
          state.enable()
        else
          @beforeEnablingFirst (err) =>
            if err
              switch err
                when 'cannot-connect' then state.alert(CannotConnectAlert)
                when 'cannot-download' then state.alert("Cannot download livereload.js")
            else
              state.useFallback = @useFallback
              state.enable()

  tabStatus: (tab) ->
    unless @isAvailable(tab)
      return Status.unavailable
    @findState(tab)?.status() || Status.disabled

  updateStatus: (tab, status) ->
    @findState(tab, yes).updateStatus(status)

  areAnyTabsEnabled: ->
    return yes for tabState in @_tabs when tabState.enabled
    no

  beforeEnablingFirst: (callback) ->
    @useFallback = no

    # probe using web sockets
    callbackCalled = no
    ws = {}

    failOnTimeout = ->
      console.log "Haven't received a handshake reply in time, disconnecting."
      ws.close()
    timeout = setTimeout(failOnTimeout, 1000)

    chrome.storage.sync.get {https: false}, (items) =>
        scheme = if items.https then "wss" else "ws"
        console.log "Connecting to " + scheme + "://#{@host}:#{@port}/livereload..."
        ws = new TheWebSocket(scheme + "://#{@host}:#{@port}/livereload")
        ws.onerror = =>
          console.log "Web socket error."
          callback('cannot-connect') unless callbackCalled
          callbackCalled = yes
        ws.onopen = =>
          console.log "Web socket connected, sending handshake."
          ws.send JSON.stringify({ command: 'hello', protocols: ['http://livereload.com/protocols/connection-check-1'] })
        ws.onclose = ->
          console.log "Web socket disconnected."
          callback('cannot-connect') unless callbackCalled
          callbackCalled = yes
        ws.onmessage = (event) =>
          clearTimeout(timeout) if timeout
          timeout = null

          console.log "Incoming message: #{event.data}"
          if event.data.match(/^!!/)
            @useFallback = yes
            callback(null) unless callbackCalled
            callbackCalled = yes
            ws.close()
          else if event.data.match(/^\{/)
            xhr = new XMLHttpRequest()
            xhr.onreadystatechange = =>
              if xhr.readyState is XMLHttpRequest.DONE and xhr.status is 200
                @script = xhr.responseText
                callback(null) unless callbackCalled
                callbackCalled = yes
            xhr.onerror = (event) =>
              callback('cannot-download') unless callbackCalled
              callbackCalled = yes
            chrome.storage.sync.get {https: false}, (items) =>
              url = if items.https then "https" else "http"
              url += "://#{@host}:#{@port}/livereload.js"
              console.debug('Get livereload.js from', url)
              xhr.open("GET", url, true)
              xhr.send(null)


  afterDisablingLast: ->


  received: (eventName, data) ->
    if func = @["on #{eventName}"]
      func.call(this, data)

  'on resourceAdded': ({ url }) ->
    console.log "Resource added: #{url}"
    # if @client.connected
    #   if @client.negotiatedProtocols?.connCheck >= 1
    #     @client.send { command: "presave", url }
    #   else
    #     console.log "Saving protocol not supported."
    # else
    #   @client.open()

  'on resourceUpdated': ({ url, content }) ->
    console.log "Resource updated: #{url}"
    # if @client.connected
    #   if @client.negotiatedProtocols?.connCheck >= 1
    #     @client.send { command: "save", url, content }
    #   else
    #     console.log "Saving protocol not supported."
    # else
    #   @client.open()


exports.TabState = TabState
exports.LiveReloadGlobal = LiveReloadGlobal
