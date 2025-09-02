# frozen_string_literal: true

class PortfoliosController < ApplicationController
  before_action :set_portfolio
  before_action :authenticate_user!

  def show
    @positions = @portfolio.positions
  end

  private

  def set_portfolio
    @portfolio = Portfolio.find(params[:id])
  end
end
