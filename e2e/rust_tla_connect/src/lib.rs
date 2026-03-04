use serde::{Deserialize, Serialize};
use tla_connect::{switch, Driver, DriverError, ExtractState, State, Step};

#[derive(Debug, PartialEq, Deserialize, Serialize)]
pub struct CounterState {
    pub counter: i64,
}

impl State for CounterState {}

impl ExtractState<BoundedCounter> for CounterState {
    fn from_driver(driver: &BoundedCounter) -> Result<Self, DriverError> {
        Ok(driver.snapshot())
    }
}

#[derive(Debug, Default)]
pub struct BoundedCounter {
    value: i64,
}

impl BoundedCounter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn increment(&mut self) {
        if self.value < 3 {
            self.value += 1;
        }
    }

    pub fn decrement(&mut self) {
        if self.value > 0 {
            self.value -= 1;
        }
    }

    pub fn snapshot(&self) -> CounterState {
        CounterState {
            counter: self.value,
        }
    }
}

impl Driver for BoundedCounter {
    type State = CounterState;

    fn step(&mut self, step: &Step) -> Result<(), DriverError> {
        switch!(step {
            "init" => {
                self.value = 0;
                Ok(())
            },
            "increment" => {
                self.increment();
                Ok(())
            },
            "decrement" => {
                self.decrement();
                Ok(())
            },
        })
    }
}
