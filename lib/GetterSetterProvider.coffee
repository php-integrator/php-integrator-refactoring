AbstractProvider = require './AbstractProvider'

View = require './GetterSetterProvider/View'

module.exports =

##*
# Provides getter and setter (accessor and mutator) generation capabilities.
##
class GetterSetterProvider extends AbstractProvider
    ###*
     * The view that allows the user to select the properties to generate for.
    ###
    selectionView: null

    ###*
     * Aids in building methods.
    ###
    functionBuilder: null

    ###*
     * The docblock builder.
    ###
    docblockBuilder: null

    ###*
     * The type helper.
    ###
    typeHelper: null

    ###*
     * @param {Object} typeHelper
     * @param {Object} functionBuilder
     * @param {Object} docblockBuilder
    ###
    constructor: (@typeHelper, @functionBuilder, @docblockBuilder) ->

    ###*
     * @inheritdoc
    ###
    activate: (service) ->
        super(service)

        @selectionView = new View(@onConfirm.bind(this), @onCancel.bind(this))
        @selectionView.setLoading('Loading class information...')
        @selectionView.setEmptyMessage('No properties found.')

        atom.commands.add 'atom-workspace', "php-integrator-refactoring:generate-getter": =>
            @executeCommand(true, false)

        atom.commands.add 'atom-workspace', "php-integrator-refactoring:generate-setter": =>
            @executeCommand(false, true)

        atom.commands.add 'atom-workspace', "php-integrator-refactoring:generate-getter-setter-pair": =>
            @executeCommand(true, true)

    ###*
     * @inheritdoc
    ###
    deactivate: () ->
        super()

        if @selectionView
            @selectionView.destroy()
            @selectionView = null

    ###*
     * @inheritdoc
    ###
    getIntentionProviders: () ->
        return [{
            grammarScopes: ['source.php']
            getIntentions: ({textEditor, bufferPosition}) =>
                successHandler = (currentClassName) =>
                    return [] if not currentClassName

                    return [
                        {
                            priority : 100
                            icon     : 'gear'
                            title    : 'Generate Getter And Setter Pair(s)'

                            selected : () =>
                                @executeCommand(true, true)
                        }

                        {
                            priority : 100
                            icon     : 'gear'
                            title    : 'Generate Getter(s)'

                            selected : () =>
                                @executeCommand(true, false)
                        },

                        {
                            priority : 100
                            icon     : 'gear'
                            title    : 'Generate Setter(s)'

                            selected : () =>
                                @executeCommand(false, true)
                        }
                    ]

                failureHandler = () ->
                    return []

                activeTextEditor = atom.workspace.getActiveTextEditor()

                return [] if not activeTextEditor
                return [] if not @getCurrentProjectPhpVersion()?

                return @service.determineCurrentClassName(activeTextEditor, activeTextEditor.getCursorBufferPosition()).then(successHandler, failureHandler)
        }]

    ###*
     * Executes the generation.
     *
     * @param {boolean} enableGetterGeneration
     * @param {boolean} enableSetterGeneration
    ###
    executeCommand: (enableGetterGeneration, enableSetterGeneration) ->
        activeTextEditor = atom.workspace.getActiveTextEditor()

        return if not activeTextEditor

        @selectionView.setMetadata({editor: activeTextEditor})
        @selectionView.storeFocusedElement()
        @selectionView.present()

        successHandler = (currentClassName) =>
            return if not currentClassName

            nestedSuccessHandler = (classInfo) =>
                enabledItems = []
                disabledItems = []

                indentationLevel = activeTextEditor.indentationForBufferRow(activeTextEditor.getCursorBufferPosition().row)

                for name, property of classInfo.properties
                    getterName = 'get' + name.substr(0, 1).toUpperCase() + name.substr(1)
                    setterName = 'set' + name.substr(0, 1).toUpperCase() + name.substr(1)

                    getterExists = if getterName of classInfo.methods then true else false
                    setterExists = if setterName of classInfo.methods then true else false

                    data = {
                        name             : name
                        types            : property.types
                        needsGetter      : enableGetterGeneration
                        needsSetter      : enableSetterGeneration
                        getterName       : getterName
                        setterName       : setterName
                        tabText          : activeTextEditor.getTabText()
                        indentationLevel : indentationLevel
                        maxLineLength    : atom.config.get('editor.preferredLineLength', activeTextEditor.getLastCursor().getScopeDescriptor())
                    }

                    if (enableGetterGeneration and enableSetterGeneration and getterExists and setterExists) or
                       (enableGetterGeneration and getterExists) or
                       (enableSetterGeneration and setterExists)
                        data.className = 'php-integrator-refactoring-strikethrough'
                        disabledItems.push(data)

                    else
                        data.className = ''
                        enabledItems.push(data)

                @selectionView.setItems(enabledItems.concat(disabledItems))

            nestedFailureHandler = () =>
                @selectionView.setItems([])

            @service.getClassInfo(currentClassName).then(nestedSuccessHandler, nestedFailureHandler)

        failureHandler = () =>
            @selectionView.setItems([])

        @service.determineCurrentClassName(activeTextEditor, activeTextEditor.getCursorBufferPosition()).then(successHandler, failureHandler)

    ###*
     * Indicates if the specified type is a class type or not.
     *
     * @return {bool}
    ###
    isClassType: (type) ->
        return if type.substr(0, 1).toUpperCase() == type.substr(0, 1) then true else false

    ###*
     * Called when the selection of properties is cancelled.
     *
     * @param {Object|null} metadata
    ###
    onCancel: (metadata) ->

    ###*
     * Called when the selection of properties is confirmed.
     *
     * @param {array}       selectedItems
     * @param {Object|null} metadata
    ###
    onConfirm: (selectedItems, metadata) ->
        itemOutputs = []

        enablePhp7Support = if @getCurrentProjectPhpVersion() >= 7.0 then true else false

        for item in selectedItems
            if item.needsGetter
                itemOutputs.push(@generateGetterForItem(item, enablePhp7Support))

            if item.needsSetter
                itemOutputs.push(@generateSetterForItem(item, enablePhp7Support))

        output = itemOutputs.join("\n").trim()

        metadata.editor.getBuffer().insert(metadata.editor.getCursorBufferPosition(), output)

    ###*
     * Generates a getter for the specified selected item.
     *
     * @param {Object}  item
     * @param {boolean} enablePhp7Support
     *
     * @return {string}
    ###
    generateGetterForItem: (item, enablePhp7Support) ->
        typeSpecification = @typeHelper.buildTypeSpecificationFromTypeArray(item.types)

        returnType = null

        if enablePhp7Support
            returnTypeHint = @typeHelper.getTypeHintForTypeSpecification(typeSpecification, enablePhp7Support)

            if returnTypeHint? and not returnTypeHint.isNullable
                returnType = returnTypeHint.typeHint

        statements = [
            "return $this->#{item.name};"
        ]

        functionText = @functionBuilder
            .makePublic()
            .setIsStatic(false)
            .setIsAbstract(false)
            .setName(item.getterName)
            .setReturnType(returnType)
            .setParameters([])
            .setStatements(statements)
            .setTabText(item.tabText)
            .setIndentationLevel(item.indentationLevel)
            .setMaxLineLength(item.maxLineLength)
            .build()

        docblockText = @docblockBuilder.buildForMethod(
            [],
            typeSpecification,
            false,
            item.tabText.repeat(item.indentationLevel)
        )

        return docblockText + functionText

    ###*
     * Generates a setter for the specified selected item.
     *
     * @param {Object}  item
     * @param {boolean} enablePhp7Support
     *
     * @return {string}
    ###
    generateSetterForItem: (item, enablePhp7Support) ->
        typeSpecification = @typeHelper.buildTypeSpecificationFromTypeArray(item.types)

        parameterTypeHint = @typeHelper.getTypeHintForTypeSpecification(typeSpecification, enablePhp7Support)

        parameterType = if parameterTypeHint? then parameterTypeHint.typeHint else null
        defaultValue  = if parameterTypeHint? and parameterTypeHint.isNullable then 'null' else null

        returnType = null

        # if enablePhp7Support
            # returnType = 'self'

        statements = [
            "$this->#{item.name} = $#{item.name};"
            "return $this;"
        ]

        parameters = [
            {
                name         : '$' + item.name
                typeHint     : parameterType
                defaultValue : defaultValue
            }
        ]

        functionText = @functionBuilder
            .makePublic()
            .setIsStatic(false)
            .setIsAbstract(false)
            .setName(item.setterName)
            .setReturnType(returnType)
            .setParameters(parameters)
            .setStatements(statements)
            .setTabText(item.tabText)
            .setIndentationLevel(item.indentationLevel)
            .setMaxLineLength(item.maxLineLength)
            .build()

        docblockText = @docblockBuilder.buildForMethod(
            [{name : '$' + item.name, type : typeSpecification}],
            'static',
            false,
            item.tabText.repeat(item.indentationLevel)
        )

        return docblockText + functionText
