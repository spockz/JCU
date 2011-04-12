class RulesListItemView extends Backbone.View
  tagName: 'li'

  initialize: ->
    @model.view = @

  render: =>
    $(@el).html app.templates.rulesListItem(content: @model.toJSON())
    console.log @model.toJSON()
    @

  remove: ->
    $(@el).remove()

  clear: ->
    @model.clear()

