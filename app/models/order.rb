# == Schema Information
#
# Table name: orders
#
#  id                      :integer          not null, primary key
#  total                   :decimal(10, )
#  special_instruction     :text(65535)
#  state                   :string(255)
#  user_id                 :integer
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  address_id              :integer
#  state_shipment_price_id :integer
#  payment_time            :datetime
#  receipt_number          :string(255)
#  transfer_time           :datetime
#  transferred             :boolean
#  cancel_time             :datetime
#  shipment_price_value    :decimal(10, )
#  shipment_price_code     :string(255)
#  shipment_price_courier  :string(255)
#  shipment_price_name     :string(255)
#  shipment_price_etd      :string(255)
#

class Order < ActiveRecord::Base

  # Relation
  has_many :line_items, dependent: :destroy
  accepts_nested_attributes_for :line_items
  has_many :products, through: :line_items
  has_many :suppliers, through: :products, source: :user
  belongs_to :address
  belongs_to :user
  belongs_to :state_shipment_price

  # scope
  scope :vendor, -> { where(state: [:delivery, :done, :failed]) }
  scope :created, -> { order(created_at: :desc) }

  # Method

  def self.admin
    where(state: [:payment, :delivery, :done, :failed])
  end

  def finish_order
    line_items.each do |line_item|

      line_item.product.stock -= line_item.quantity
      line_item.product.published = false if line_item.product.stock == 0

      line_item.product.save

    end
  end

  def cancel_order
    if state == 'delivery'
      cancel
      self.cancel_time = Time.zone.now
      user.credit += total
      save && user.save
    else
      false
    end
  end

  # State
  include AASM

  def self.states
    [:cart, :address, :payment, :delivery, :done, :failed]
  end

  def state_simple
    if state == 'cart'
      'Di dalam keranjang'
    elsif state == 'address'
      'Masukkan alamat'
    elsif state == 'payment'
      'Pembayaran'
    elsif state == 'delivery'
      'Masukkan nomor resi'
    elsif state == 'done'
      'Selesai'
    elsif state == 'failed'
      'Batal'
    end
  end

  aasm column: :state do # default column: aasm_state

    state :cart, initial: true
    state :address
    state :payment
    state :delivery
    state :done
    state :failed

    event :checkout do
      transitions from: :cart, to: :address
    end

    event :addressing do
      transitions to: :payment
    end

    event :pay do
      transitions to: :delivery
    end

    event :deliver do
      before do
        finish_order
      end
      transitions to: :done
    end

    event :cancel do
      transitions to: :failed
    end

  end

  def transfer
    ActiveRecord::Base.transaction do
      supplier = suppliers.first
      supplier.credit += total
      supplier.save
      self.transferred = true
      self.transfer_time = Time.zone.now
      save
    end
  end

  def same_vendor?(line_item)
    return true if suppliers.blank?
    suppliers.ids.include?(line_item.product.user_id)
  end

  def total_without_shipment
    line_items.inject(0) { |result, element| result + element.price }
  end

  def total
    total_without_shipment + shipment_price
  end

  def total_weight_gram
    line_items.inject(0) { |result, element| result + (element.quantity * element.product.weight) }
  end

  def total_weight
    line_items.inject(0) { |result, element| result + (element.quantity * element.product.weight) } / 1000.0
  end

  def display_weight
    weight = total_weight
    return 1.0 if weight < 1.0

    if weight % 1 < 0.3
      weight = weight.floor
    else
      weight = weight.ceil
    end
    weight
  end

  def shipment_price
    # return 0 if state_shipment_price.nil?
    # weight = display_weight
    # weight * state_shipment_price.price
    if shipment_price_value.present?
      return shipment_price_value
    elsif state_shipment_price.present?
      weight = display_weight
      return weight * state_shipment_price.price
    else
      return 0
    end

    # shipment_price_value.present? ? shipment_price_value : 0
  end

  def valid_with_credit
    user.credit < total
  end

end
