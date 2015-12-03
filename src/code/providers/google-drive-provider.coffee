{div, button, span} = React.DOM

tr = require '../utils/translate'
isString = require '../utils/is-string'

ProviderInterface = (require './provider-interface').ProviderInterface
CloudMetadata = (require './provider-interface').CloudMetadata

GoogleDriveAuthorizationDialog = React.createFactory React.createClass
  displayName: 'GoogleDriveAuthorizationDialog'

  getInitialState: ->
    loadedGAPI: false

  componentWillMount: ->
    @props.provider._loadedGAPI =>
      @setState loadedGAPI: true

  authenticate: ->
    @props.provider.authorize GoogleDriveProvider.SHOW_POPUP

  render: ->
    (div {},
      if @state.loadedGAPI
        (button {onClick: @authenticate}, 'Authorization Needed')
      else
        'Waiting for the Google Client API to load...'
    )

class GoogleDriveProvider extends ProviderInterface

  constructor: (@options = {}) ->
    super
      name: GoogleDriveProvider.Name
      displayName: @options.displayName or (tr '~PROVIDER.GOOGLE_DRIVE')
      capabilities:
        save: true
        load: true
        list: true
        remove: true
        rename: true

    @authToken = null
    @user = null
    @clientId = @options.clientId
    if not @clientId
      throw new Error 'Missing required clientId in googleDrive provider options'
    @mimeType = @options.mimeType or "text/plain"
    @_loadGAPI()

  @Name: 'googleDrive'

  # aliases for boolean parameter to authorize
  @IMMEDIATE = true
  @SHOW_POPUP = false

  authorized: (@authCallback) ->
    if @authCallback
      if @authToken
        @authCallback true
      else
        @authorize GoogleDriveProvider.IMMEDIATE
    else
      @authToken isnt null

  authorize: (immediate) ->
    @_loadedGAPI =>
      args =
        client_id: @clientId
        scope: ['https://www.googleapis.com/auth/drive', 'https://www.googleapis.com/auth/userinfo.profile']
        immediate: immediate
      gapi.auth.authorize args, (authToken) =>
        @authToken = if authToken and not authToken.error then authToken else null
        @user = null
        if @authToken
          gapi.client.oauth2.userinfo.get().execute (user) =>
            @user = user
        @authCallback @authToken isnt null

  renderAuthorizationDialog: ->
    (GoogleDriveAuthorizationDialog {provider: @})

  renderUser: ->
    if @user
      (span {}, (span {className: 'gdrive-icon'}), @user.name)
    else
      null

  save:  (content, metadata, callback) ->
    @_loadedGAPI =>
      @_sendFile content, metadata, callback

  load: (metadata, callback) ->
    @_loadedGAPI =>
      request = gapi.client.drive.files.get
        fileId: metadata.providerData.id
      request.execute (file) =>
        if file?.downloadUrl
          @_downloadFromUrl file.downloadUrl, @authToken, callback
        else
          callback 'Unable to get download url'

  list: (metadata, callback) ->
    @_loadedGAPI =>
      request = gapi.client.drive.files.list
        q: "mimeType = '#{@mimeType}'"
      request.execute (result) =>
        return callback('Unable to list files') if not result
        list = []
        for item in result?.items
          # TODO: for now don't allow folders
          if item.mimeType isnt 'application/vnd.google-apps.folder'
            list.push new CloudMetadata
              name: item.title
              path: ""
              type: if item.mimeType is 'application/vnd.google-apps.folder' then CloudMetadata.Folder else CloudMetadata.File
              provider: @
              providerData:
                id: item.id
        list.sort (a, b) ->
          lowerA = a.name.toLowerCase()
          lowerB = b.name.toLowerCase()
          return -1 if lowerA < lowerB
          return 1 if lowerA > lowerB
          return 0
        callback null, list

  remove: (metadata, callback) ->
    @_loadedGAPI ->
      request = gapi.client.drive.files.delete
        fileId: metadata.providerData.id
      request.execute (result) ->
        callback? result?.error or null

  rename: (metadata, newName, callback) ->
    @_loadedGAPI ->
      request = gapi.client.drive.files.patch
        fileId: metadata.providerData.id
        resource:
          title: newName
      request.execute (result) ->
        if result?.error
          callback? result.error
        else
          metadata.name = newName
          callback null, metadata

  _loadGAPI: ->
    if not window._LoadingGAPI
      window._LoadingGAPI = true
      window._GAPIOnLoad = ->
        @window._LoadedGAPI = true
      script = document.createElement 'script'
      script.src = 'https://apis.google.com/js/client.js?onload=_GAPIOnLoad'
      document.head.appendChild script

  _loadedGAPI: (callback) ->
    if window._LoadedGAPIClients
      callback()
    else
      self = @
      check = ->
        if window._LoadedGAPI
          gapi.client.load 'drive', 'v2', ->
            gapi.client.load 'oauth2', 'v2', ->
              window._LoadedGAPIClients = true
              callback.call self
        else
          setTimeout check, 10
      setTimeout check, 10

  _downloadFromUrl: (url, token, callback) ->
    xhr = new XMLHttpRequest()
    xhr.open 'GET', url
    if token
      xhr.setRequestHeader 'Authorization', "Bearer #{token.access_token}"
    xhr.onload = ->
      callback null, xhr.responseText
    xhr.onerror = ->
      callback "Unable to download #{url}"
    xhr.send()

  _sendFile: (content, metadata, callback) ->
    boundary = '-------314159265358979323846'
    header = JSON.stringify
      title: metadata.name
      mimeType: @mimeType

    [method, path] = if metadata.providerData?.id
      ['PUT', "/upload/drive/v2/files/#{metadata.providerData.id}"]
    else
      ['POST', '/upload/drive/v2/files']

    body = [
      "\r\n--#{boundary}\r\nContent-Type: application/json\r\n\r\n#{header}",
      "\r\n--#{boundary}\r\nContent-Type: #{@mimeType}\r\n\r\n#{content}",
      "\r\n--#{boundary}--"
    ].join ''

    request = gapi.client.request
      path: path
      method: method
      params: {uploadType: 'multipart'}
      headers: {'Content-Type': 'multipart/related; boundary="' + boundary + '"'}
      body: body

    request.execute (file) ->
      if callback
        if file?.error
          callback "Unabled to upload file: #{file.error.message}"
        else if file
          callback null, file
        else
          callback 'Unabled to upload file'

module.exports = GoogleDriveProvider