fs = require "fs"
im = require "imagemagick"
Watch = require('fs-watcher').watch
Seq = require "seq"
checksum = require './checksum'
{ EventEmitter } = require "events"

Image = require './image'

class Sprite extends EventEmitter
  images = []
  
  constructor: (@name, @path, @mapper, @watch = false) ->

  reload: ->
    console.log "read start"
    @_readImages (err, images) =>
      console.log "read done"
      return
      unless err
        @images = images
        @mapper.map @images
        @emit "update"
  
  load: (cb = ->) ->
    @_fromJson()
    @_readImages (err, images) =>
      unless err
        @images = images
        @mapper.map @images
        @_watch()
      cb err

  url: ->
    "#{@path}/#{@filename()}"

  jsonUrl: ->
    "#{@path}/#{@name}.json"

  filename: ->
    "#{@name}-#{@shortsum()}.png"
      
  write: (cb) ->
    fs.exists @url(), (exists) =>
      if exists
        cb()
      else
        @_write cb

  _write: (cb) ->
    commands = @_emptySprite()
    @_addImageData(commands, image) for image in @images
    commands.push @url()
    im.convert commands, (err) =>
      @_toJson()
      @_cleanup()
      cb err
  
  image: (name) ->
    result = @images.filter (i) -> i.name == name
    result[0]

  checksum: ->
    sums = (img.checksum for img in @images)
    checksum.array sums

  shortsum: ->
    @checksum()[0...5]
  
  _watch: ->
    return unless @watch
    return if @_watcher?
    @_watcher = new Watch(root: "#{@path}/#{@name}")
    @_watcher.on "create", (o) => @reload()
    @_watcher.on "change", (o) => @reload()
    @_watcher.start();

  _width: ->
    @mapper.width
  
  _height: ->
    @mapper.height

  _emptySprite: ->
    ["-size", "#{@_width()}x#{@_height()}", "xc:none"]
    
  _addImageData: (commands, image) ->
    commands.push image.file(), "-geometry", "+#{image.positionX}+#{image.positionY}", "-composite"
    
  _readImages: (cb) ->
    Seq()
      .seq_ (next) =>
        @_getFiles next
      .flatten()
      .parMap_ (next, filename) =>
        @_getImage filename, next
      .unflatten()
      .seq_ (next, images) =>
        # workaround for https://github.com/substack/node-seq/issues/22
        error = null
        for image in images
          error = new Error("unable to read all images") unless image?
        cb error, images
  
  _getFiles: (cb) ->
    fs.readdir "#{@path}/#{@name}", (err, files) ->
      files = files.filter (file) -> file.match /\.(png|gif|jpg|jpeg)$/
      cb err, files

  _cleanup: (cb = ->) ->
    self = @
    fs.readdir "#{@path}", (err, files) ->
      for file in files
        if file.match("^#{self.name}-.*\.png$") and file isnt self.filename()
          fs.unlinkSync "#{self.path}/#{file}"
      cb()

  _getImage: (filename, cb) ->
    image = new Image(filename, "#{@path}/#{@name}")
    image.readDimensions (err) ->
      # workaround for https://github.com/substack/node-seq/issues/22
      if err
        cb()
      else
        cb null, image

  _toJson: ->
    info = 
      name: @name
      checksum: @checksum()
      shortsum: @shortsum()
      images: []

    for image in @images
      imageInfo =
        name: image.name
        filename: image.filename
        checksum: image.checksum
        width: image.width
        height: image.height
        positionX: image.positionX
        positionY: image.positionY
      info.images.push imageInfo

    info = JSON.stringify(info, null, '  ')
    fs.writeFileSync @jsonUrl(), info

  _fromJson: ->
    try
      info = fs.readFileSync @jsonUrl(), "UTF-8"
    catch error
      return # no json file

    info = JSON.parse info
    @images = []
    for img in info.images
      image = new Image(img.filename, "#{@path}/#{@name}")
      image.width = img.width
      image.height = img.height
      image.checksum = img.checksum
      image.positionX = img.positionX
      image.positionY = img.positionY
      @images.push image 

module.exports = Sprite