require 'andand'

module Rspreadsheet

class RowOrNode
  def mode
   case
     when xmlnode.nil? then :outbound
     when repeated>1  then :repeated
     else :regular
   end
  end
end

class Cell < RowOrNode
  attr_accessor :worksheet, :rowi, :coli
  def initialize(aworksheet,arowi,acoli)
    @worksheet = aworksheet
    @rowi = arowi
    @coli = acoli
  end
  def row; @worksheet.rows(rowi) end
  def coordinates; [rowi,coli] end

  def xmlnode; @worksheet.cellxmlnode(@rowi,@coli) end
  def value
    gt = guess_cell_type
    if (self.mode == :regular) or (self.mode == :repeated)
      case 
        when gt == nil then nil
        when gt == Float then xmlnode.attributes['value'].to_f
        when gt == String then xmlnode.elements.first.andand.content.to_s
        when gt == Date then Date.strptime(xmlnode.attributes['date-value'].to_s, '%Y-%m-%d')
        when gt == 'percentage' then xmlnode.attributes['value'].to_f
      end
    elsif self.mode == :outbound
      nil
    else
      raise "Unknown cell mode #{self.mode}"
    end
  end
  def repeated; (Tools.get_ns_attribute_value(xmlnode, 'table', 'number-columns-repeated') || 1 ).to_i end
  def guess_cell_type(avalue=nil)
    # try guessing by value
    valueguess = case avalue
      when Numeric then Float
      when Date then Date
      when String,nil then nil
      else nil
    end
    result = valueguess

    if valueguess.nil? # valueguess is most important
      # if not succesfull then try guessing by type
      type = xmlnode.nil? ? nil : xmlnode.attributes['value-type'].to_s 
      typeguess = case type
        when nil then nil
        when 'float' then Float
        when 'string' then String
        when 'date' then Date
        when 'percentage' then :percentage
        else 
          if xmlnode.children.size == 0
            nil
          else 
            raise "Unknown type from #{@xmlnode.to_s} / children size=#{@xmlnode.children.size.to_s} / type=#{type}"
          end
      end

      result =
      if !typeguess.nil? # if not certain by value, but have a typeguess
        if !avalue.nil?  # with value we may try converting
          if (typeguess(avalue) rescue false) # if convertible then it is typeguess
            typeguess
          elsif (String(avalue) rescue false) # otherwise try string
            String
          else # if not convertible to anything concious then nil
            nil 
          end
        else             # without value we just beleive typeguess
          typeguess
        end
      else # it not have a typeguess
        if (String(avalue) rescue false) # convertible to String
          String
        else
          nil
        end
      end
    end
    result
  end
  def detach_if_needed
    if (self.mode == :repeated) or (self.mode == :outbound ) # Cell did not exist individually yet, detach row and create editable cell
      @worksheet.detach_cell_in_xml(rowi,coli)
    end
 end
  def value=(avalue)
    detach_if_needed
    if self.mode == :regular
      gt = guess_cell_type(avalue)
      case
        when gt == nil then raise 'This value type is not storable to cell'
        when gt == Float 
          set_type_attribute('float')
          remove_all_value_attributes_and_content(xmlnode)
          Tools.set_ns_attribute(xmlnode,'office','value', avalue.to_s) 
          xmlnode << LibXML::XML::Node.new('p', avalue.to_f.to_s, ns_text)
        when gt == String then
          set_type_attribute('string')
          remove_all_value_attributes_and_content(xmlnode)
          xmlnode << LibXML::XML::Node.new('p', avalue.to_s, ns_text)
        when gt == Date then 
          set_type_attribute('date')
          remove_all_value_attributes_and_content(xmlnode)
          Tools.set_ns_attribute(xmlnode,'office','date-value', avalue.strftime('%Y-%m-%d'))
          xmlnode << LibXML::XML::Node.new('p', avalue.strftime('%Y-%m-%d'), ns_text) 
        when gt == 'percentage'
          set_type_attribute('float')
          remove_all_value_attributes_and_content(xmlnode)
          Tools.set_ns_attribute(xmlnode,'office','value', avalue.to_f.to_s) 
          xmlnode << LibXML::XML::Node.new('p', (avalue.to_f*100).round.to_s+'%', ns_text)
      end
    else
      raise "Unknown cell mode #{self.mode}"
    end
  end
  def set_type_attribute(typestring)
    Tools.set_ns_attribute(xmlnode,'office','value-type',typestring)
  end
  def remove_all_value_attributes_and_content(node)
    if att = Tools.get_ns_attribute(node, 'office','value') then att.remove! end
    if att = Tools.get_ns_attribute(node, 'office','date-value') then att.remove! end
    node.content=''
  end
  def ns_table; xmlnode.doc.root.namespaces.find_by_prefix('table') end
  def ns_office; xmlnode.doc.root.namespaces.find_by_prefix('office') end
  def ns_text; xmlnode.doc.root.namespaces.find_by_prefix('text') end
  def relative(rowdiff,coldiff)
    @worksheet.cells(self.rowi+rowdiff, self.coli+coldiff)
  end
  def is_repeated?; mode == :repeated end

end
  
  
# class Cell
#   attr_reader :col, :xmlnode
#   attr_reader  :parent_row  # for debug only
#   attr_accessor :mode
#   def self.empty_cell_node
#     LibXML::XML::Node.new('table-cell',nil, Tools.get_namespace('table'))
#   end
#   def initialize(aparent_row,coli,axmlnode=nil)
#     raise "First parameter should be Row object not #{aparent_row.class}" unless aparent_row.kind_of?(Rspreadsheet::Row)
#     @parent_row = aparent_row
#     if axmlnode.nil?
#       axmlnode = Cell.empty_cell_node
#     end
#     @xmlnode = axmlnode
#     @col = coli
#     # set @mode
#     @mode = case
#       when !@parent_row.used_col_range.include?(coli) then :outbound
#       when Tools.get_ns_attribute_value(@xmlnode, 'table', 'number-columns-repeated').to_i>1  then :repeated
#       else:regular
#     end
#   end
#   def to_s; value end
#   def cell_xml; self.xmlnode.to_s end
#   def xml; self.xmlnode.children.first.andand.inner_xml end
#   def address; Rspreadsheet::Tools.c2a(row,col) end
#   def row; @parent_row.row end
#   def worksheet; @parent_row.worksheet end
#   def type
#     case 
#       when guess_cell_type == Float  then :float
#       when guess_cell_type == String then :string
#       when guess_cell_type == Date   then :date
#       when guess_cell_type == 'percentage' then :percentage
#       when guess_cell_type == nil then :empty
#       else :unknown
#     end
#   end
#   # use this to find node in cell xml. ex. xmlfind('.//text:a') finds all link nodes
#   def xmlfindall(path)
#     xmlnode.find(path)
#   end
#   def xmlfindfirst(path)
#     xmlfindall(path).first
#   end
#   # based on @xmlnode and optionally value which is about to be assigned, guesses which type the result should be
#   def inspect
#     "#<Rspreadsheet::Cell:Cell\n row:#{row}, col:#{col} address:#{address}\n type: #{guess_cell_type.to_s}, value:#{value}\n mode: #{mode}\n>"
#   end
# end

end












