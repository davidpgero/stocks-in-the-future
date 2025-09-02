# frozen_string_literal: true

require "test_helper"

class PurchaseStockTest < ActiveSupport::TestCase
  test "it creates a withdrawal transaction in portfolio_transactions" do
    student = create(:student)
    create(:portfolio, user: student)
    student.portfolio.portfolio_transactions.create!(amount_cents: 1000, transaction_type: :deposit)
    stock = create(:stock, price_cents: 100)
    order = create(:order, :pending, action: :buy, shares: 5, stock: stock, user: student)

    assert_difference("PortfolioTransaction.count") do
      PurchaseStock.execute(order)
    end

    portfolio_transaction = PortfolioTransaction.last
    assert portfolio_transaction.withdrawal?
    assert_equal portfolio_transaction, order.portfolio_transaction
    assert_operator portfolio_transaction.amount_cents, :>, 0
  end

  test "it creates an linked entry in portfolio_stocks" do
    student = create(:student)
    create(:portfolio, user: student)
    student.portfolio.portfolio_transactions.create!(amount_cents: 1000, transaction_type: :deposit)
    stock = create(:stock, price_cents: 100)
    order = create(:order, :pending, action: :buy, shares: 5, stock: stock, user: student)

    assert_difference("PortfolioStock.count") do
      PurchaseStock.execute(order)
    end

    portfolio_stock = PortfolioStock.last
    assert_equal portfolio_stock, order.portfolio_stock
  end

  test "it updates the order status to completed" do
    student = create(:student)
    create(:portfolio, user: student)
    student.portfolio.portfolio_transactions.create!(amount_cents: 1000, transaction_type: :deposit)
    stock = create(:stock, price_cents: 100)
    order = create(:order, :pending, action: :buy, shares: 5, stock: stock, user: student)

    PurchaseStock.execute(order)
    order.reload

    assert order.completed?
  end

  test "it does not update order when status is not pending" do
    student = create(:student)
    student.portfolio.portfolio_transactions.create!(amount_cents: 1000, transaction_type: :deposit)
    stock = create(:stock, price_cents: 100)
    order = create(:order, :completed, action: :buy, shares: 5, stock: stock, user: student)

    PurchaseStock.execute(order)
    order.reload

    assert order.completed?
  end

  test "it handles transaction rollback when portfolio stock creation fails" do
    portfolio = create(:portfolio)
    portfolio.portfolio_transactions.create!(amount_cents: 1000, transaction_type: :deposit)

    stock = create(:stock, price_cents: 100)
    order = create(:order, :pending, :buy, shares: 5, stock: stock, user: portfolio.user)

    # Mock PortfolioStock creation to fail
    PortfolioStock.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid.new(PortfolioStock.new))

    assert_raises(ActiveRecord::RecordInvalid) do
      PurchaseStock.execute(order)
    end

    order.reload

    assert_equal "pending", order.status
    # Since we removed the after_create callback, portfolio_transaction is only created by the service
    # When the service fails, no portfolio_transaction should be created
    assert_nil order.portfolio_transaction
    assert_nil order.portfolio_stock
  end

  test "buy order creates positive shares in portfolio_stock" do
    portfolio = create(:portfolio)
    portfolio.portfolio_transactions.create!(amount_cents: 1000, transaction_type: :deposit)
    stock = create(:stock, price_cents: 100)
    order = create(:order, :pending, :buy, shares: 5, stock: stock, user: portfolio.user)

    PurchaseStock.execute(order)

    portfolio_stock = PortfolioStock.last
    assert_equal 5, portfolio_stock.shares
    assert_equal stock, portfolio_stock.stock
  end

  test "sell order creates negative shares in portfolio_stock" do
    portfolio = create(:portfolio)
    stock = create(:stock, price_cents: 100)
    create(:portfolio_stock, portfolio: portfolio, stock: stock, shares: 10, purchase_price: 100)

    order = create(:order, :pending, :sell, shares: 3, stock: stock, user: portfolio.user)

    PurchaseStock.execute(order)

    # Should have 2 portfolio_stock records now (original + new sell record)
    portfolio_stocks = PortfolioStock.where(portfolio: portfolio, stock: stock)
    assert_equal 2, portfolio_stocks.count

    sell_record = portfolio_stocks.order(:created_at).last
    assert_equal(-3, sell_record.shares)
    assert_equal stock, sell_record.stock
  end

  # test "multiple buy orders create separate portfolio_stock records" do
  #   portfolio = create(:portfolio)
  #   portfolio.portfolio_transactions.create!(amount_cents: 1000, transaction_type: :deposit)
  #   stock = create(:stock, price_cents: 100)

  #   order1 = create(:order, :pending, :buy, shares: 5, stock: stock, user: portfolio.user)
  #   PurchaseStock.execute(order1)

  #   order2 = create(:order, :pending, :buy, shares: 3, stock: stock, user: portfolio.user)
  #   PurchaseStock.execute(order2)

  #   portfolio_stocks = PortfolioStock.where(stock: stock, portfolio: portfolio)
  #   assert_equal 2, portfolio_stocks.count
  #   assert_equal [3, 5], portfolio_stocks.pluck(:shares).sort
  # end

  test "buy then sell orders work together correctly" do
    portfolio = create(:portfolio)
    portfolio.portfolio_transactions.create!(amount_cents: 2000, transaction_type: :deposit)
    stock = create(:stock, price_cents: 100)

    buy_order = create(:order, :pending, :buy, shares: 10, stock: stock, user: portfolio.user)
    PurchaseStock.execute(buy_order)

    sell_order = create(:order, :pending, :sell, shares: 4, stock: stock, user: portfolio.user)
    PurchaseStock.execute(sell_order)

    portfolio_stocks = PortfolioStock.where(stock: stock, portfolio: portfolio)
    assert_equal 2, portfolio_stocks.count

    shares_values = portfolio_stocks.pluck(:shares).sort
    assert_equal [-4, 10], shares_values

    total_shares = portfolio.position_for(stock).total_shares
    assert_equal 6, total_shares
  end
end
