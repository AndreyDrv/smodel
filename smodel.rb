module SModel
	# Model class extension for specific model behavior
	# @author Andrey Glushkov
	module BaseModel
	  def self.included(base)
		included_modules.each { |mod| base.extend(mod) }
		base.extend(ClassMethods)
		puts included_modules
	  end

		#DSL methods
	  module ClassMethods
		attr_accessor :elements, :elements_config

		  #Add new element to Model
		  # <p>Use configuration params:</p>
		  # @param [Symbol] name field name
		  # @param [Class] type typeof field
		  # @param [Hash] options special flags
		def element(name, type, options={})
		  dsl_initialize unless @elements
		  @fields = [] unless @fields
		  element = initialize_element type, options
		  @elements[name] = element
		  @fields << name unless @fields.include? name
		end

		  #Add new branch (one element with multiple fields) element to Model
		  # <p>Use configuration params:</p>
		  # @param [Symbol] name field name
		  # @param [Class] type typeof field
		  # @param [Hash] options special flags
		def branch(name, type, options={})
		  element name, type, {:branch => true}.merge(options)
		end
		  
		  #Add new branch (one element with multiple fields) element to Model in ActiveModel style
		  # <p>Use configuration params:</p>
		  # @param [Symbol] name field name
		  # @param [Class] type typeof field
		  # @param [Hash] options special flags
		def has_one(name, type, options={})
		  element name, type, {:branch => true}.merge(options)
		end
		
		  #Add array of elements to Model in ActiveModel style
		  # <p>Use configuration params:</p>
		  # @param [Symbol] name field name
		  # @param [Class] type typeof field
		  # @param [Hash] options special flags
		def has_many(name, type, options={})
		  element name, type, {:many => true}.merge(options)
		end

		def dsl_initialize
		  @elements = {}
		  @elements_config = {}
		end

		  #Get alias_text associated with key or path
		  # <p>Use configuration params:</p>
		  # @param [Symbol, String] element_key field name or path
		def alias_text(element_key)
		  if (element_key.match(%r'>'))
			branchmap = element_key.split('>')
			current = branchmap.shift
			current = current.strip.intern

			branchmap.shift if @elements[current][:options].has_key? :many
			@elements[current][:type].alias_text branchmap.join('>')
		  else
			element_key = element_key.strip.intern unless element_key.class.eql? Symbol
			return @elements[element_key][:options][:alias_text] if @elements[element_key][:options][:alias_text] if @elements[element_key]
			nil
		  end
		end

		def initialize_element(type, options={})
		  element = {}
		  element[:type] = type
		  element[:options] = options

		  element
		end

		  #Get fields list
		  # <p>Use configuration params:</p>
		  # @param [String] param merge field with path
		def fields param = ""
		  return @fields.collect { |x| param + x.to_s } unless param.empty?
		  @fields
		end

		def has_defaults
		  @elements.each { |key, value|
			return true if value[:options][:default_value]
		  }
		end

	  end


		# child model should not have initialize. if you really need it do not forget super.
	  def initialize
		@elements = self.class.elements
		@elements_config = self.class.elements_config
		@elements_data = {}
		@elements_branchmap = {}
	  end

		#Get field type
		# <p>Use configuration params:</p>
		# @param [Symbol, String] key field name or path
	  def get_type key #TODO: make recursive
		@elements[key.intern][:type]
	  end

		#Set field options
		# <p>Use configuration params:</p>
		# @param [Symbol, String] key field name or path
		# @param [Hash] value field name or path
	  def set_options key, value #TODO: make recursive
		@elements[key][:options].merge value
	  end

		#Set field value
		# <p>Use configuration params:</p>
		# @param [Symbol, String] name field name or path
		# @param [String] value value of field
	  def set_value(name, value, params=nil)
		if name.is_a? Symbol
		  raise NameError, "Model #{self.class.name} unknown field name `#{name}`" unless @elements[name]
		  type = @elements[name][:type]
		  @elements_data[name] = typecast type, value_mutator(name, value)
		else
		  branchmap = name.split('>')

		  if branchmap.size > 1
			current = branchmap.shift
			current = current.strip.intern

			  #if model collection
			if @elements[current][:options].has_key? :many
			  n = branchmap.shift.to_i
			  @elements_data[current] = Array.new unless @elements_data[current]
			  if value.respond_to? :set_value #force assign if this is completed basemodel object

				if @elements_data[current][n]
				  #if force=> true then do not merge
				  if params[:force]
					@elements_data[current][n] = value
				  else
					@elements_data[current][n].merge(value)
				  end

				else
				  @elements_data[current][n] = value
				end
			  else #continue process if this is simple value
				@elements_data[current][n] = @elements[current][:type].new unless @elements_data[current][n]
				if @elements_data[current][n].respond_to? :set_value
				  @elements_data[current][n].set_value branchmap.join('>'), value, params
				else
				  @elements_data[current][n] = value
				end
			  end
			else
			  @elements_data[current] = @elements[current][:type].new unless @elements_data[current]
			  @elements_data[current].set_value branchmap.join('>'), value, params
			end

		  else
			current = name.strip.intern
			set_value current, value, params
		  end

		end
	  end

		#Mutate string value by key
		# <p>Use configuration params:</p>
		# @param [String] key element key
		# @param [String] value element value
	  def value_mutator key, value
		value
	  end

	  def initialize_path path
		set_value path, ""
	  end

		#Get proper value type
		#based on happymapper
		# <p>Use configuration params:</p>
		# @param [Class] type type of value
		# @param [String] value value of field
	  def typecast(type, value)

		begin
		  if    type == String then
			value.to_s
		  elsif type == Float then
			value.to_f
		  elsif type == Time then
			Time.parse(value.to_s)
		  elsif type == Date then
			Date.parse(value.to_s)
		  elsif type == DateTime then
			date = DateTime.parse(value).to_time
			  #date.
			date
		  elsif type == Boolean then
			['true', 't', '1'].include?(value.to_s.downcase)
		  elsif type == Integer
			# ganked from datamapper
			value_to_i = value.to_i
			if value_to_i == 0 && value != '0'
			  value_to_s = value.to_s
			  begin
				Integer(value_to_s =~ /^(\d+)/ ? $1 : value_to_s)
			  rescue ArgumentError
				nil
			  end
			else
			  value_to_i
			end
		  else
			value
		  end
		rescue
		  value
		end
	  end

		#Match values with hash
		# <p>Use configuration params:</p>
		# @param [Hash] hash key-value hash
	  def match_hash? hash, target=self
		hash.each do |key, value|
		  res = value == target.match_value(key, value)
		  res = match_hash?(value, @elements_data[key]) if value.class.eql? Hash and @elements_data[key]

		  return res unless res
		end
		true
	  end

		#Match key value object`s data?
		# <p>Use configuration params:</p>
		# @param [String] key key
		# @param [String] value key
	  def match_value? key, value
		@elements_data[key] == value
	  end

		#Apply values with hash
		# <p>Use configuration params:</p>
		# @param [Hash] hash key-value hash
	  def apply_hash!(hash)
		hash.each { |key, value| set_value key, value }
	  end

	  def apply_collection_to(collection, to)
		collection.each { |item| @elements_data[item] }
	  end

		#Set default values of instance
		# <p>Use configuration params:</p>
		# @param [Class] item_instance item instance to fill default values in
	  def init_defaults item_instance
		return nil unless item_instance
		item = item_instance.class
		item.fields.each do |field|
		  default_value = item_instance.init_default(field)

		  item_instance.set_value field, default_value if default_value

		end
		item_instance
	  end

		#Get default value of field
		# <p>Use configuration params:</p>
		# @param [String] field field name
	  def init_default(field)
		nil
		if @elements[field.intern][:options][:default_value].class.eql? Symbol
		  return send(@elements[field.intern][:options][:default_value])
		else #if @elements[field.intern][:options][:default_value].class.eql? String
		  return @elements[field.intern][:options][:default_value]
		end


	  end

		#Get model values hash
		# <p>Use configuration params:</p>
	  def to_hash
		result = {}
		@elements.each { |item, attr|

		  result[item] = @elements_data[item] unless attr[:options].has_key? :branch
		  if attr[:options].has_key?(:branch)
			if attr[:options].has_key?(:many)
			  result[item] = Array.new
			  if @elements_data[item]
				@elements_data[item].each { |n|
				  if n.respond_to? :to_hash
					result[item] << n.to_hash
				  else
					result[item] << n
				  end
				}
			  end
			else
			  unless @elements_data[item]
				item_class = @elements[item][:type]
				item_instance = item_class.new if item_class
				@elements_data[item] = init_defaults(item_instance) if item_class.has_defaults and item_instance
			  end

			  result[item] = @elements_data[item]
			  result[item] = @elements_data[item].to_hash if @elements_data[item]
			end
		  end
		  result[item] = init_default item unless @elements_data[item]
		}

		result
	  end
	end
end