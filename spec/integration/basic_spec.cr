require "./spec_helper"

describe "a basic C++ wrapper" do
  it "works" do
    build_and_run("basic") do
      context "core functionality" do
        it "supports static methods" do
          Test::AdderWrap.sum(4, 5).should eq(9)
        end

        it "supports member methods" do
          Test::AdderWrap.new(4).sum(5).should eq(9)
        end
      end

      context "if class has implicit default constructor" do
        it "has a default constructor" do
          Test::ImplicitConstructor.new.it_works.should eq(1)
        end
      end

      context "crystal wrapper features" do
        it "adds #initialize(unwrap: Binding::T*)" do
          {{
            Test::AdderWrap.methods.any? do |m|
              m.name == "initialize" && \
              m.args.size == 1 && \
              m.args.any? do |a|
                a.name.stringify == "unwrap"
              end
            end
          }}.should be_true
        end
      end

      context "method filtering" do
        methods = {{ Test::AdderWrap.methods.map(&.name.stringify) }}
        it "removes argument value type" do
          methods.includes?("ignoreByArgument").should be_false
        end
      end
    end
  end
end
